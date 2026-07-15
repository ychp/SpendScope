import Foundation
import XCTest
@testable import SpendScope

final class CodexImporterTests: XCTestCase {
    func testImportsUsageQuotaAndSessionOnceAcrossRefreshes() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionDesktop,
            .turn(model: "gpt-synthetic"),
            .started,
            .token(input: 1_000, cached: 600, output: 100, reasoning: 40, plan: "plus"),
            .completed,
            .unknown
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)

        let first = await importer.refresh(scope: .history)
        let second = await importer.refresh(scope: .history)

        XCTAssertTrue(first.isSuccessful)
        XCTAssertEqual(first.processedFileCount, 1)
        XCTAssertEqual(first.discoveredFileIDs?.count, 1)
        XCTAssertEqual(second.skippedFileCount, 1)
        XCTAssertEqual(try store.totalUsage(), 1_100)
        XCTAssertEqual(try store.latestQuotas().map(\.observation.kind), [.fiveHour, .weekly])
        XCTAssertEqual(try store.sessions().first?.activity, .completed)
        XCTAssertEqual(try store.sessions().first?.sourceKind, .desktop)
        XCTAssertEqual(try store.usageEventCount(), 1)
        XCTAssertEqual(try store.quotaEventCount(), 2)
        XCTAssertEqual(try store.sessionStateEventCount(), 2)
    }

    func testAppendAddsOnlyPositiveDeltaAndArchiveMoveDoesNotDuplicate() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 1_000, cached: 500, output: 100, reasoning: 20, plan: nil)
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)

        try fixture.append(.token(
            input: 1_500,
            cached: 700,
            output: 160,
            reasoning: 30,
            plan: nil,
            second: 6
        ))
        _ = await importer.refresh(scope: .history)
        try fixture.archiveRollout()
        _ = await importer.refresh(scope: .history)

        XCTAssertEqual(try store.totalUsage(), 1_660)
        XCTAssertEqual(try store.sessions().first?.archive, .archived)
        XCTAssertEqual(try store.usageEventCount(), 2)
    }

    func testMalformedKnownEventStopsAtBadLineAndReportsOnlyControlledDetail() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let goodOffset = try fixture.rolloutSize()
        let secret = "SENSITIVE-SENTINEL"
        try fixture.appendRaw("{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"secret\":\"\(secret)\"}\n")
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)

        let result = await importer.refresh(scope: .history)
        let checkpoint = try XCTUnwrap(try store.sessions().first?.sourceFileID)
        let file = try XCTUnwrap(try store.fileCheckpoint(fileID: checkpoint))

        XCTAssertEqual(result.issues.map(\.kind), [.decode])
        XCTAssertFalse(result.issues[0].detail.contains(secret))
        XCTAssertFalse(result.issues[0].detail.contains(fixture.codexRoot.path))
        XCTAssertEqual(file.committedOffset, goodOffset)
        XCTAssertEqual(file.formatStatus, "error")
        XCTAssertEqual(file.lastError, "malformed-event")
        XCTAssertEqual(try store.totalUsage(), 120)

        let retry = await importer.refresh(scope: .history)
        XCTAssertEqual(retry.issues.map(\.kind), [.decode])
        XCTAssertEqual(try store.fileCheckpoint(fileID: checkpoint)?.committedOffset, goodOffset)
        XCTAssertEqual(try store.usageEventCount(), 1)
    }

    func testTruncationRebuildsDerivedUsageFromReplacement() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 1_000, cached: 500, output: 100, reasoning: 20, plan: "plus")
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)
        let fileID = try XCTUnwrap(try store.sessions().first?.sourceFileID)

        try fixture.replace(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 10, cached: 4, output: 2, reasoning: 1, plan: nil, second: 8)
        ])
        _ = await importer.refresh(scope: .history)

        let reset = try XCTUnwrap(try store.fileCheckpoint(fileID: fileID))
        XCTAssertEqual(reset.generation, 0)
        XCTAssertEqual(reset.committedOffset, try fixture.rolloutSize())
        XCTAssertEqual(reset.counters?.input, 10)
        XCTAssertEqual(try store.totalUsage(), 12)

        _ = await importer.refresh(scope: .history)
        XCTAssertEqual(try store.totalUsage(), 12)
        XCTAssertEqual(try store.fileCheckpoint(fileID: fileID)?.generation, 0)
    }

    func testExplicitPlanSurvivesImporterRestartWhenLaterSnapshotOmitsPlan() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)

        try fixture.append(.token(
            input: 200,
            cached: 80,
            output: 40,
            reasoning: 10,
            plan: nil,
            second: 7
        ))
        _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)

        XCTAssertEqual(try store.hourlyUsage().map(\.plan), [.plus])
        XCTAssertEqual(try store.threadCheckpoint(threadID: CodexFixture.threadID)?.currentPlan?.kind, .plus)
    }

    func testForegroundSelectsNewestOldCandidateAndHistoryDeduplicatesOtherSource() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: 1_000))
        _ = try fixture.duplicateRollout(
            named: "newer-old.jsonl",
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)

        let foreground = await importer.refresh(scope: .foreground)
        let history = await importer.refresh(scope: .history)

        XCTAssertEqual(foreground.processedFileCount, 1)
        XCTAssertEqual(foreground.skippedFileCount, 1)
        XCTAssertEqual(history.processedFileCount, 1)
        XCTAssertEqual(history.skippedFileCount, 1)
        XCTAssertEqual(try store.totalUsage(), 120)
        XCTAssertEqual(try store.usageEventCount(), 1)
    }

    func testExactFileThreadMappingSurvivesOtherRolloutWinningSessionThenRestart() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .started,
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: 3_000))
        let second = try fixture.duplicateRollout(
            named: "second.jsonl",
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
        let secondFileID = try XCTUnwrap(
            CodexSourceDiscovery().discover(rootURL: fixture.codexRoot).rollouts
                .first { $0.url.lastPathComponent == second.lastPathComponent }?.fileID
        )
        XCTAssertEqual(try store.sessions().first?.sourceFileID, secondFileID)

        try fixture.append(.token(
            input: 200,
            cached: 80,
            output: 40,
            reasoning: 10,
            plan: nil,
            second: 7
        ))
        try fixture.append(.completed)
        let result = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
        let firstRollout = try XCTUnwrap(
            CodexSourceDiscovery().discover(rootURL: fixture.codexRoot).rollouts
                .first { $0.url.lastPathComponent == fixture.rolloutURL.lastPathComponent }
        )

        XCTAssertTrue(result.isSuccessful)
        XCTAssertEqual(try store.fileCheckpoint(fileID: firstRollout.fileID)?.threadID, CodexFixture.threadID)
        XCTAssertEqual(try store.totalUsage(), 240)
        XCTAssertEqual(try store.usageEventCount(), 2)
        XCTAssertEqual(try store.sessions().first?.activity, .completed)
    }

    func testTokenCheckpointsRemainIsolatedAcrossFilesForSameThread() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        let second = try fixture.duplicateRollout(
            named: "second.jsonl",
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)

        try fixture.append(.token(
            input: 200,
            cached: 80,
            output: 40,
            reasoning: 10,
            plan: nil,
            second: 7
        ))
        _ = await importer.refresh(scope: .history)

        try fixture.append(.token(
            input: 150,
            cached: 60,
            output: 30,
            reasoning: 8,
            plan: nil,
            second: 8
        ), to: second)
        _ = await importer.refresh(scope: .history)

        XCTAssertEqual(try store.totalUsage(), 300)
        let checkpoints = try CodexSourceDiscovery().discover(rootURL: fixture.codexRoot).rollouts
            .compactMap { try store.fileCheckpoint(fileID: $0.fileID) }
        XCTAssertEqual(Set(checkpoints.compactMap { $0.counters?.input }), [150, 200])
    }

    func testEmbeddedSessionMetadataOverridesStaleIndexThreadWithoutDroppingUsage() async throws {
        let fixture = try CodexFixture.make(events: [
            .sessionCLI,
            .turn(model: "gpt-synthetic"),
            .token(input: 100, cached: 40, output: 20, reasoning: 5, plan: "plus")
        ])
        try fixture.installIndex(
            archived: false,
            childEdgeStatus: "closed",
            updatedAtMilliseconds: 9_000,
            threadID: "stale-index-thread"
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)

        let first = await importer.refresh(scope: .history)
        let second = await importer.refresh(scope: .history)

        XCTAssertTrue(first.isSuccessful)
        XCTAssertEqual(second.skippedFileCount, 1)
        XCTAssertEqual(try store.totalUsage(), 120)
        XCTAssertEqual(try store.sessions().map(\.threadID), [CodexFixture.threadID])
        let fileID = try XCTUnwrap(store.sessions().first?.sourceFileID)
        XCTAssertEqual(try store.fileCheckpoint(fileID: fileID)?.threadID, CodexFixture.threadID)
    }

    func testArchiveFactAggregatesAcrossSameThreadFilesInEitherOrderAndRestart() async throws {
        for archivedIsNewer in [false, true] {
            let fixture = try CodexFixture.make(events: [.sessionCLI, .turn(model: "gpt-synthetic")])
            try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: archivedIsNewer ? 1_000 : 3_000))
            _ = try fixture.duplicateRolloutToArchive(
                named: "archived.jsonl",
                modificationDate: Date(timeIntervalSince1970: archivedIsNewer ? 3_000 : 1_000)
            )
            let store = try UsageStore(databaseURL: fixture.databaseURL)

            _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
            XCTAssertEqual(try store.sessions().first?.archive, .archived)
            let observedAt = try XCTUnwrap(store.sessions().first?.state.archiveObservedAtMilliseconds)
            XCTAssertEqual(observedAt, 3_000_000)

            _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
            XCTAssertEqual(try store.sessions().first?.archive, .archived)
            XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, observedAt)
        }
    }

    func testIndexArchiveAndChildFactsUpdateWithoutNewJSONLLines() async throws {
        let fixture = try CodexFixture.make(events: [.sessionCLI, .turn(model: "gpt-synthetic")])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)
        let checkpointBefore = try XCTUnwrap(
            try store.fileCheckpoint(fileID: XCTUnwrap(store.sessions().first?.sourceFileID))
        )
        let rolloutModifiedAt = try XCTUnwrap(
            CodexSourceDiscovery().discover(rootURL: fixture.codexRoot).rollouts.first
        ).modificationTimeMilliseconds

        try fixture.installIndex(archived: true, childEdgeStatus: "open", updatedAtMilliseconds: 9_000)
        _ = await importer.refresh(scope: .history)

        let session = try XCTUnwrap(store.sessions().first)
        XCTAssertEqual(session.archive, .archived)
        XCTAssertEqual(session.childEdgeStatus, "open")
        XCTAssertEqual(session.state.archiveObservedAtMilliseconds, max(9_000, rolloutModifiedAt))
        XCTAssertEqual(
            try store.fileCheckpoint(fileID: checkpointBefore.fileID)?.committedOffset,
            checkpointBefore.committedOffset
        )
    }

    func testNewerExplicitActiveIndexRestoresThreadAfterArchivedFileDisappears() async throws {
        let fixture = try CodexFixture.make(events: [.sessionCLI, .turn(model: "gpt-synthetic")])
        try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: 3_000))
        let archived = try fixture.duplicateRolloutToArchive(
            named: "archived.jsonl",
            modificationDate: Date(timeIntervalSince1970: 2_000)
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)
        XCTAssertEqual(try store.sessions().first?.archive, .archived)
        XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, 3_000_000)

        try FileManager.default.removeItem(at: archived)
        try fixture.installIndex(
            archived: false,
            childEdgeStatus: "closed",
            updatedAtMilliseconds: 4_000_000
        )
        _ = await importer.refresh(scope: .history)

        XCTAssertEqual(try store.sessions().first?.archive, .active)
        XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, 4_000_000)
    }

    func testFilesystemArchiveOverridesNewerActiveWhenIndexBecomesUnavailable() async throws {
        for degraded in [false, true] {
            let fixture = try CodexFixture.make(events: [.sessionCLI, .turn(model: "gpt-synthetic")])
            try fixture.setRolloutModificationDate(Date(timeIntervalSince1970: 3_000))
            try fixture.installIndex(
                archived: false,
                childEdgeStatus: "open",
                updatedAtMilliseconds: 4_000_000
            )
            let store = try UsageStore(databaseURL: fixture.databaseURL)
            _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)
            XCTAssertEqual(try store.sessions().first?.archive, .active)
            XCTAssertEqual(try store.sessions().first?.childEdgeStatus, "open")
            XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, 4_000_000)

            try fixture.makeIndexUnavailable(degraded: degraded)
            try fixture.archiveRollout()
            let inventory = try CodexSourceDiscovery().discover(rootURL: fixture.codexRoot)
            if degraded {
                guard case .degraded = inventory.indexHealth else {
                    return XCTFail("expected degraded index")
                }
            } else {
                XCTAssertEqual(inventory.indexHealth, .missing)
            }
            _ = await CodexImporter(rootURL: fixture.codexRoot, store: store).refresh(scope: .history)

            XCTAssertEqual(try store.sessions().first?.archive, .archived)
            XCTAssertEqual(try store.sessions().first?.childEdgeStatus, "open")
            XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, 4_000_000)
        }
    }
}

private final class CodexFixture: @unchecked Sendable {
    static let threadID = "00000000-0000-0000-0000-000000000001"

    let codexRoot: URL
    let databaseURL: URL
    private(set) var rolloutURL: URL

    private init(codexRoot: URL, databaseURL: URL, rolloutURL: URL) {
        self.codexRoot = codexRoot
        self.databaseURL = databaseURL
        self.rolloutURL = rolloutURL
    }

    static func make(events: [Event]) throws -> CodexFixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SpendScope-CodexImporterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let rollout = root.appending(path: "sessions/2026/07/14/rollout.jsonl")
        try FileManager.default.createDirectory(
            at: rollout.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fixture = CodexFixture(
            codexRoot: root,
            databaseURL: root.appending(path: "usage.sqlite3"),
            rolloutURL: rollout
        )
        try fixture.replace(events: events)
        return fixture
    }

    func append(_ event: Event) throws {
        try appendRaw(event.line + "\n")
    }

    func append(_ event: Event, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((event.line + "\n").utf8))
    }

    func appendRaw(_ value: String) throws {
        let handle = try FileHandle(forWritingTo: rolloutURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(value.utf8))
    }

    func replace(events: [Event]) throws {
        let data = Data((events.map(\.line).joined(separator: "\n") + "\n").utf8)
        try data.write(to: rolloutURL)
    }

    func archiveRollout() throws {
        let archived = codexRoot.appending(path: "archived_sessions/rollout.jsonl")
        try FileManager.default.createDirectory(
            at: archived.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: rolloutURL, to: archived)
        rolloutURL = archived
    }

    func setRolloutModificationDate(_ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: rolloutURL.path)
    }

    func duplicateRollout(named name: String, modificationDate: Date) throws -> URL {
        let duplicate = rolloutURL.deletingLastPathComponent().appending(path: name)
        try FileManager.default.copyItem(at: rolloutURL, to: duplicate)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: duplicate.path)
        return duplicate
    }

    func duplicateRolloutToArchive(named name: String, modificationDate: Date) throws -> URL {
        let duplicate = codexRoot.appending(path: "archived_sessions/\(name)")
        try FileManager.default.createDirectory(
            at: duplicate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: rolloutURL, to: duplicate)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: duplicate.path)
        return duplicate
    }

    func installIndex(
        archived: Bool,
        childEdgeStatus: String,
        updatedAtMilliseconds: Int64,
        threadID: String = CodexFixture.threadID
    ) throws {
        let database = try SQLiteDatabase(url: codexRoot.appending(path: "state_1.sqlite"))
        try database.execute(sql: """
            CREATE TABLE threads(
              id TEXT NOT NULL, rollout_path TEXT NOT NULL, source TEXT NOT NULL, model TEXT,
              created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL, archived INTEGER NOT NULL
            )
            """)
        try database.execute(
            sql: "INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(threadID), .text(rolloutURL.path), .text("cli"), .text("gpt-index"),
                .integer(1_000), .integer(updatedAtMilliseconds), .integer(archived ? 1 : 0)
            ]
        )
        try database.execute(sql: "CREATE TABLE thread_spawn_edges(child_thread_id TEXT, status TEXT)")
        try database.execute(
            sql: "INSERT INTO thread_spawn_edges VALUES (?, ?)",
            bindings: [.text(threadID), .text(childEdgeStatus)]
        )
    }

    func makeIndexUnavailable(degraded: Bool) throws {
        let fileManager = FileManager.default
        for name in ["state_1.sqlite", "state_1.sqlite-wal", "state_1.sqlite-shm"] {
            let url = codexRoot.appending(path: name)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        if degraded {
            let database = try SQLiteDatabase(url: codexRoot.appending(path: "state_2.sqlite"))
            try database.execute(sql: "CREATE TABLE unrelated(value TEXT)")
        }
    }

    func rolloutSize() throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: rolloutURL.path)
        return try XCTUnwrap((attributes[.size] as? NSNumber)?.int64Value)
    }

    enum Event {
        case sessionDesktop
        case sessionCLI
        case turn(model: String)
        case started
        case completed
        case unknown
        case token(
            input: Int64,
            cached: Int64,
            output: Int64,
            reasoning: Int64,
            plan: String?,
            second: Int = 4
        )

        var line: String {
            switch self {
            case .sessionDesktop:
                return """
                {"type":"session_meta","payload":{"id":"\(CodexFixture.threadID)","originator":"Codex Desktop","cli_version":"1.0.0"}}
                """
            case .sessionCLI:
                return """
                {"type":"session_meta","payload":{"id":"\(CodexFixture.threadID)","source":"cli","cli_version":"1.0.0"}}
                """
            case let .turn(model):
                return """
                {"type":"turn_context","payload":{"turn_id":"turn-1","model":"\(model)"}}
                """
            case .started:
                return """
                {"timestamp":"2026-07-14T01:02:03.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}
                """
            case .completed:
                return """
                {"timestamp":"2026-07-14T01:02:05.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
                """
            case .unknown:
                return """
                {"type":"future_event","payload":{"synthetic":true}}
                """
            case let .token(input, cached, output, reasoning, plan, second):
                let planField = plan.map { ",\"plan_type\":\"\($0)\"" } ?? ""
                return """
                {"timestamp":"2026-07-14T01:02:\(String(format: "%02d", second)).000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning)}},"rate_limits":{"primary":{"used_percent":25,"window_minutes":300,"resets_at":2000000000},"secondary":{"used_percent":50,"window_minutes":10080,"resets_at":2000100000}\(planField)}}}
                """
            }
        }
    }
}
