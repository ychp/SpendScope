import CryptoKit
import Foundation

enum ImportScope: Sendable, Equatable {
    case foreground
    case history
}

enum ImportIssueKind: String, Sendable {
    case discovery
    case index
    case read
    case decode
    case store
    case unsupportedFormat
}

struct ImportIssue: Sendable, Equatable {
    let kind: ImportIssueKind
    let fileID: String?
    let detail: String
}

struct ImportResult: Sendable {
    let scope: ImportScope
    let processedFileCount: Int
    let skippedFileCount: Int
    let issues: [ImportIssue]
    let indexHealth: CodexIndexHealth

    var isSuccessful: Bool { issues.isEmpty }
}

actor CodexImporter {
    private let rootURL: URL
    private let store: UsageStore
    private let discovery: CodexSourceDiscovery
    private let reader: IncrementalJSONLReader
    private let decoder: CodexEventDecoder
    private let calendar: Calendar

    init(
        rootURL: URL,
        store: UsageStore,
        discovery: CodexSourceDiscovery = CodexSourceDiscovery(),
        reader: IncrementalJSONLReader = IncrementalJSONLReader(),
        decoder: CodexEventDecoder = CodexEventDecoder(),
        calendar: Calendar = .current
    ) {
        self.rootURL = rootURL
        self.store = store
        self.discovery = discovery
        self.reader = reader
        self.decoder = decoder
        self.calendar = calendar
    }

    func refresh(scope: ImportScope) async -> ImportResult {
        let inventory: CodexSourceInventory
        do {
            inventory = try discovery.discover(rootURL: rootURL)
        } catch {
            return ImportResult(
                scope: scope,
                processedFileCount: 0,
                skippedFileCount: 0,
                issues: [.init(kind: .discovery, fileID: nil, detail: "discovery-failed")],
                indexHealth: .degraded("discovery failed")
            )
        }

        var issues: [ImportIssue] = []
        if case .degraded = inventory.indexHealth {
            issues.append(.init(kind: .index, fileID: nil, detail: "index-degraded"))
        }

        let selected = selectedRollouts(from: inventory.rollouts, scope: scope)
        var processed = 0
        var skipped = inventory.rollouts.count - selected.count
        for rollout in selected {
            switch importRollout(rollout, inventory: inventory) {
            case .processed(let issue):
                processed += 1
                if let issue { issues.append(issue) }
            case .skipped:
                skipped += 1
            case .failed(let issue):
                issues.append(issue)
            }
        }

        return ImportResult(
            scope: scope,
            processedFileCount: processed,
            skippedFileCount: skipped,
            issues: issues,
            indexHealth: inventory.indexHealth
        )
    }

    private func selectedRollouts(from rollouts: [RolloutFile], scope: ImportScope) -> [RolloutFile] {
        let sorted = rollouts.sorted {
            if $0.modificationTimeMilliseconds != $1.modificationTimeMilliseconds {
                return $0.modificationTimeMilliseconds > $1.modificationTimeMilliseconds
            }
            return $0.fileID < $1.fileID
        }
        guard scope == .foreground, !sorted.isEmpty else { return sorted }

        let startOfDay = calendar.startOfDay(for: Date())
        let startMilliseconds = Int64((startOfDay.timeIntervalSince1970 * 1_000).rounded())
        let newestFileID = sorted[0].fileID
        return sorted.filter {
            $0.modificationTimeMilliseconds >= startMilliseconds || $0.fileID == newestFileID
        }
    }

    private func importRollout(
        _ rollout: RolloutFile,
        inventory: CodexSourceInventory
    ) -> FileImportOutcome {
        let previousFile: FileCheckpoint?
        let storedSessions: [StoredSession]
        do {
            previousFile = try store.fileCheckpoint(fileID: rollout.fileID)
            storedSessions = try store.sessions()
        } catch {
            return .failed(.init(kind: .store, fileID: rollout.fileID, detail: "checkpoint-read-failed"))
        }

        let storedByThread = Dictionary(uniqueKeysWithValues: storedSessions.map { ($0.threadID, $0) })
        let storedForFile = storedSessions.first { $0.sourceFileID == rollout.fileID }
        if canSkip(
            rollout,
            previousFile: previousFile,
            storedSession: storedForFile,
            inventory: inventory
        ) {
            return .skipped
        }

        let readBatch: JSONLReadBatch
        do {
            readBatch = try reader.read(
                file: rollout.url,
                fromOffset: previousFile?.committedOffset ?? 0
            )
        } catch {
            return .failed(.init(kind: .read, fileID: rollout.fileID, detail: "read-failed"))
        }

        let now = currentMilliseconds()
        if readBatch.wasTruncated {
            let threadID = storedForFile?.threadID ?? rollout.thread?.threadID
            var checkpoints: [ThreadCheckpoint] = []
            if let threadID {
                do {
                    let previousThread = try store.threadCheckpoint(threadID: threadID)
                    checkpoints = [ThreadCheckpoint(
                        threadID: threadID,
                        currentModel: previousThread?.currentModel,
                        currentPlan: previousThread?.currentPlan,
                        counters: nil,
                        counterSegment: (previousThread?.counterSegment ?? 0) + 1,
                        lastTokenAtMilliseconds: previousThread?.lastTokenAtMilliseconds
                    )]
                } catch {
                    return .failed(.init(
                        kind: .store,
                        fileID: rollout.fileID,
                        detail: "checkpoint-read-failed"
                    ))
                }
            }
            let file = makeFileCheckpoint(
                rollout: rollout,
                committedOffset: 0,
                generation: (previousFile?.generation ?? 0) + 1,
                lastRecordAtMilliseconds: previousFile?.lastRecordAtMilliseconds,
                lastSuccessAtMilliseconds: now,
                formatStatus: "supported",
                lastError: nil
            )
            do {
                try store.commit(ImportBatch(
                    file: file,
                    usageEvents: [],
                    quotaEvents: [],
                    stateEvents: [],
                    sessions: [],
                    threadCheckpoints: checkpoints
                ))
                return .processed(issue: nil)
            } catch {
                return .failed(.init(kind: .store, fileID: rollout.fileID, detail: "transaction-failed"))
            }
        }

        var context: ImportContext
        do {
            context = try makeContext(
                rollout: rollout,
                storedSession: storedForFile,
                storedByThread: storedByThread
            )
        } catch {
            return .failed(.init(
                kind: .store,
                fileID: rollout.fileID,
                detail: "checkpoint-read-failed"
            ))
        }
        var usageEvents: [StoredUsageEvent] = []
        var quotaEvents: [StoredQuotaEvent] = []
        var stateEvents: [StoredSessionStateEvent] = []
        var committedOffset = previousFile?.committedOffset ?? 0
        var lineIssue: ImportIssue?

        for line in readBatch.lines {
            let event: CodexDecodedEvent?
            do {
                event = try decoder.decode(line: line.data)
            } catch {
                lineIssue = .init(kind: .decode, fileID: rollout.fileID, detail: "malformed-event")
                break
            }

            guard let event else {
                committedOffset = line.endOffset
                continue
            }

            do {
                try consume(
                    event,
                    lineOffset: line.endOffset,
                    rollout: rollout,
                    storedByThread: storedByThread,
                    context: &context,
                    usageEvents: &usageEvents,
                    quotaEvents: &quotaEvents,
                    stateEvents: &stateEvents
                )
                committedOffset = line.endOffset
            } catch let issue as ImportContextIssue {
                lineIssue = .init(
                    kind: .unsupportedFormat,
                    fileID: rollout.fileID,
                    detail: issue.detail
                )
                break
            } catch {
                lineIssue = .init(kind: .store, fileID: rollout.fileID, detail: "checkpoint-read-failed")
                break
            }
        }

        applyInventoryFacts(
            rollout: rollout,
            inventory: inventory,
            storedSession: storedForFile,
            context: &context
        )

        var sessions: [StoredSession] = []
        var threadCheckpoints: [ThreadCheckpoint] = []
        if let threadID = context.threadID {
            sessions = [StoredSession(
                threadID: threadID,
                sourceKind: context.source,
                createdAtMilliseconds: context.createdAtMilliseconds,
                updatedAtMilliseconds: context.updatedAtMilliseconds,
                state: context.state ?? .empty(threadID: threadID),
                lastModel: context.model,
                lastPlan: context.lastPlan,
                sourceFileID: rollout.fileID
            )]
            threadCheckpoints = [ThreadCheckpoint(
                threadID: threadID,
                currentModel: context.model,
                currentPlan: context.currentPlan,
                counters: context.counters,
                counterSegment: context.counterSegment,
                lastTokenAtMilliseconds: context.lastTokenAtMilliseconds
            )]
        }

        let hadCompleteLine = !readBatch.lines.isEmpty
        let file = makeFileCheckpoint(
            rollout: rollout,
            committedOffset: committedOffset,
            generation: previousFile?.generation ?? 0,
            lastRecordAtMilliseconds: hadCompleteLine
                ? rollout.modificationTimeMilliseconds
                : previousFile?.lastRecordAtMilliseconds,
            lastSuccessAtMilliseconds: lineIssue == nil ? now : previousFile?.lastSuccessAtMilliseconds,
            formatStatus: lineIssue == nil ? "supported" : "error",
            lastError: lineIssue?.detail
        )

        do {
            try store.commit(ImportBatch(
                file: file,
                usageEvents: usageEvents,
                quotaEvents: quotaEvents,
                stateEvents: stateEvents,
                sessions: sessions,
                threadCheckpoints: threadCheckpoints
            ))
            return .processed(issue: lineIssue)
        } catch {
            return .failed(.init(kind: .store, fileID: rollout.fileID, detail: "transaction-failed"))
        }
    }

    private func consume(
        _ event: CodexDecodedEvent,
        lineOffset: Int64,
        rollout: RolloutFile,
        storedByThread: [String: StoredSession],
        context: inout ImportContext,
        usageEvents: inout [StoredUsageEvent],
        quotaEvents: inout [StoredQuotaEvent],
        stateEvents: inout [StoredSessionStateEvent]
    ) throws {
        switch event {
        case .session(let metadata):
            if context.threadID != metadata.threadID {
                context = try contextForSession(
                    metadata,
                    rollout: rollout,
                    storedSession: storedByThread[metadata.threadID]
                )
            }
            context.threadID = metadata.threadID
            context.source = metadata.source

        case .turn(let turn):
            guard context.threadID != nil else { throw ImportContextIssue.missingThread }
            context.model = turn.model

        case .token(let snapshot):
            guard let threadID = context.threadID else { throw ImportContextIssue.missingThread }
            let counters = snapshot.counters
            let effectivePlan: PlanResolution
            if let raw = snapshot.planRaw {
                let resolved = PlanResolver.resolve(rawValue: raw)
                if !resolved.isInferred { context.currentPlan = resolved }
                effectivePlan = resolved.isInferred ? (context.currentPlan ?? resolved) : resolved
            } else {
                effectivePlan = context.currentPlan ?? PlanResolver.resolve(rawValue: nil)
            }
            context.lastPlan = effectivePlan.kind

            if let counters {
                let previous = context.counters ?? TokenCounters(
                    input: 0,
                    cachedInput: 0,
                    output: 0,
                    reasoning: 0
                )
                if context.counters != nil, countersRolledBack(from: previous, to: counters) {
                    context.counterSegment += 1
                }
                if let delta = UsageAccumulator.delta(previous: previous, current: counters) {
                    usageEvents.append(StoredUsageEvent(
                        fingerprint: fingerprint(canonicalUsage(
                            threadID: threadID,
                            snapshot: snapshot,
                            counters: counters
                        )),
                        observedAtMilliseconds: snapshot.observedAtMilliseconds,
                        threadID: threadID,
                        sourceKind: context.source,
                        model: context.model ?? rollout.thread?.model ?? "Unknown Model",
                        plan: effectivePlan,
                        usage: delta,
                        sourceFileID: rollout.fileID,
                        sourceOffset: lineOffset
                    ))
                }
                context.counters = counters
                context.lastTokenAtMilliseconds = snapshot.observedAtMilliseconds
            }

            for raw in snapshot.quotas {
                guard let observation = QuotaNormalizer.normalize(
                    [raw],
                    plan: effectivePlan,
                    observedAtMilliseconds: snapshot.observedAtMilliseconds
                ).first else { continue }
                quotaEvents.append(StoredQuotaEvent(
                    fingerprint: fingerprint(canonicalQuota(
                        threadID: threadID,
                        observedAtMilliseconds: snapshot.observedAtMilliseconds,
                        window: raw
                    )),
                    threadID: threadID,
                    observation: observation,
                    sourceKind: context.source
                ))
            }

        case .lifecycle(let lifecycle):
            guard let threadID = context.threadID else { throw ImportContextIssue.missingThread }
            let canonical = canonicalState(threadID: threadID, event: lifecycle)
            let eventKey = fingerprint(canonical)
            context.state = SessionStateReducer.reduce(
                current: context.state ?? .empty(threadID: threadID),
                event: lifecycle,
                eventKey: eventKey
            )
            stateEvents.append(StoredSessionStateEvent(
                fingerprint: eventKey,
                threadID: threadID,
                turnID: lifecycle.turnID,
                observedAtMilliseconds: lifecycle.observedAtMilliseconds,
                kind: lifecycle.kind,
                sourceFileID: rollout.fileID,
                sourceOffset: lineOffset
            ))
        }
    }

    private func contextForSession(
        _ metadata: SessionMetadata,
        rollout: RolloutFile,
        storedSession: StoredSession?
    ) throws -> ImportContext {
        let checkpoint = try store.threadCheckpoint(threadID: metadata.threadID)
        let matchingIndex = rollout.thread?.threadID == metadata.threadID ? rollout.thread : nil
        return ImportContext(
            threadID: metadata.threadID,
            source: metadata.source,
            model: checkpoint?.currentModel ?? matchingIndex?.model,
            currentPlan: checkpoint?.currentPlan,
            lastPlan: checkpoint?.currentPlan?.kind ?? storedSession?.lastPlan,
            counters: checkpoint?.counters,
            counterSegment: checkpoint?.counterSegment ?? 0,
            lastTokenAtMilliseconds: checkpoint?.lastTokenAtMilliseconds,
            state: storedSession?.state ?? .empty(threadID: metadata.threadID),
            createdAtMilliseconds: matchingIndex?.createdAtMilliseconds ?? storedSession?.createdAtMilliseconds,
            updatedAtMilliseconds: matchingIndex?.updatedAtMilliseconds ?? storedSession?.updatedAtMilliseconds
        )
    }

    private func makeContext(
        rollout: RolloutFile,
        storedSession: StoredSession?,
        storedByThread: [String: StoredSession]
    ) throws -> ImportContext {
        let threadID = storedSession?.threadID ?? rollout.thread?.threadID
        let session = threadID.flatMap { storedByThread[$0] } ?? storedSession
        let checkpoint: ThreadCheckpoint?
        if let threadID {
            checkpoint = try store.threadCheckpoint(threadID: threadID)
        } else {
            checkpoint = nil
        }
        return ImportContext(
            threadID: threadID,
            source: session?.sourceKind ?? sourceKind(from: rollout.thread?.sourceRaw),
            model: checkpoint?.currentModel ?? session?.lastModel ?? rollout.thread?.model,
            currentPlan: checkpoint?.currentPlan,
            lastPlan: checkpoint?.currentPlan?.kind ?? session?.lastPlan,
            counters: checkpoint?.counters,
            counterSegment: checkpoint?.counterSegment ?? 0,
            lastTokenAtMilliseconds: checkpoint?.lastTokenAtMilliseconds,
            state: session?.state ?? threadID.map(SessionStateSnapshot.empty(threadID:)),
            createdAtMilliseconds: rollout.thread?.createdAtMilliseconds ?? session?.createdAtMilliseconds,
            updatedAtMilliseconds: rollout.thread?.updatedAtMilliseconds ?? session?.updatedAtMilliseconds
        )
    }

    private func applyInventoryFacts(
        rollout: RolloutFile,
        inventory: CodexSourceInventory,
        storedSession: StoredSession?,
        context: inout ImportContext
    ) {
        guard let threadID = context.threadID else { return }
        let index = rollout.thread ?? inventory.threadIndex.first { $0.threadID == threadID }
        var state = context.state ?? storedSession?.state ?? .empty(threadID: threadID)
        state = SessionStateReducer.setArchived(
            current: state,
            archived: rollout.isArchived || index?.archived == true,
            observedAtMilliseconds: rollout.modificationTimeMilliseconds
        )
        switch inventory.indexHealth {
        case .available:
            state = SessionStateReducer.setChildEdgeStatus(current: state, status: index?.childEdgeStatus)
        case .missing, .degraded:
            if let childEdgeStatus = index?.childEdgeStatus {
                state = SessionStateReducer.setChildEdgeStatus(current: state, status: childEdgeStatus)
            }
        }
        context.state = state
        context.createdAtMilliseconds = index?.createdAtMilliseconds ?? context.createdAtMilliseconds
        context.updatedAtMilliseconds = index?.updatedAtMilliseconds ?? context.updatedAtMilliseconds
        if context.model == nil { context.model = index?.model }
    }

    private func canSkip(
        _ rollout: RolloutFile,
        previousFile: FileCheckpoint?,
        storedSession: StoredSession?,
        inventory: CodexSourceInventory
    ) -> Bool {
        guard let previousFile,
              previousFile.fileSize == rollout.fileSize,
              previousFile.committedOffset == rollout.fileSize,
              previousFile.path == rollout.url.path,
              previousFile.formatStatus == "supported",
              let storedSession else {
            return false
        }
        let index = rollout.thread ?? inventory.threadIndex.first { $0.threadID == storedSession.threadID }
        let desiredArchive: SessionArchiveState = rollout.isArchived || index?.archived == true
            ? .archived
            : .active
        guard storedSession.archive == desiredArchive else { return false }
        if case .available = inventory.indexHealth {
            return storedSession.childEdgeStatus == index?.childEdgeStatus
        }
        if let explicitStatus = index?.childEdgeStatus {
            return storedSession.childEdgeStatus == explicitStatus
        }
        return true
    }

    private func makeFileCheckpoint(
        rollout: RolloutFile,
        committedOffset: Int64,
        generation: Int64,
        lastRecordAtMilliseconds: Int64?,
        lastSuccessAtMilliseconds: Int64?,
        formatStatus: String,
        lastError: String?
    ) -> FileCheckpoint {
        FileCheckpoint(
            fileID: rollout.fileID,
            deviceID: Int64(bitPattern: rollout.deviceID),
            inode: Int64(bitPattern: rollout.inode),
            path: rollout.url.path,
            fileSize: rollout.fileSize,
            committedOffset: committedOffset,
            generation: generation,
            lastRecordAtMilliseconds: lastRecordAtMilliseconds,
            lastSuccessAtMilliseconds: lastSuccessAtMilliseconds,
            formatStatus: formatStatus,
            lastError: lastError
        )
    }

    private func sourceKind(from raw: String?) -> CodexSourceKind {
        raw == "cli" ? .cli : .unknown
    }

    private func countersRolledBack(from previous: TokenCounters, to current: TokenCounters) -> Bool {
        current.input < previous.input
            || current.cachedInput < previous.cachedInput
            || current.output < previous.output
            || current.reasoning < previous.reasoning
    }

    private func canonicalUsage(
        threadID: String,
        snapshot: TokenCounterSnapshot,
        counters: TokenCounters
    ) -> String {
        "usage|\(threadID)|\(snapshot.observedAtMilliseconds)|\(counters.input)|\(counters.cachedInput)|\(counters.output)|\(counters.reasoning)"
    }

    private func canonicalQuota(
        threadID: String,
        observedAtMilliseconds: Int64,
        window: RawQuotaWindow
    ) -> String {
        "quota|\(threadID)|\(observedAtMilliseconds)|\(window.windowMinutes)|\(window.usedPercent)|\(window.resetsAtSeconds.map(String.init) ?? "nil")"
    }

    private func canonicalState(threadID: String, event: SessionLifecycleEvent) -> String {
        "state|\(threadID)|\(event.observedAtMilliseconds)|\(event.kind.rawValue)|\(event.turnID ?? "")"
    }

    private func fingerprint(_ canonical: String) -> String {
        SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func currentMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
}

private struct ImportContext {
    var threadID: String?
    var source: CodexSourceKind
    var model: String?
    var currentPlan: PlanResolution?
    var lastPlan: PlanKind?
    var counters: TokenCounters?
    var counterSegment: Int64
    var lastTokenAtMilliseconds: Int64?
    var state: SessionStateSnapshot?
    var createdAtMilliseconds: Int64?
    var updatedAtMilliseconds: Int64?
}

private enum FileImportOutcome {
    case processed(issue: ImportIssue?)
    case skipped
    case failed(ImportIssue)
}

private enum ImportContextIssue: Error {
    case missingThread

    var detail: String { "missing-thread-context" }
}
