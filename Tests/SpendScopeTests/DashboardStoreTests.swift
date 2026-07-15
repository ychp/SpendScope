import Foundation
import XCTest
@testable import SpendScope

@MainActor
final class DashboardStoreTests: XCTestCase {
    func testCodexPlanCatalogIncludesCurrentOfficialPlansAndMarksProCurrent() {
        XCTAssertEqual(
            CodexPlanCatalog.plans.map(\.name),
            ["Free", "Go", "Plus", "Pro", "Business", "Enterprise / Edu"]
        )
        XCTAssertFalse(CodexPlanCatalog.plans[0].isPaid)
        XCTAssertTrue(CodexPlanCatalog.plans.dropFirst().allSatisfy(\.isPaid))

        let currentPlans = CodexPlanCatalog.plans.filter {
            CodexPlanCatalog.isCurrent($0, currentPlanName: "Pro")
        }

        XCTAssertEqual(currentPlans.map(\.name), ["Pro"])
    }

    func testCodexPlanCatalogFallsBackToFreeWhenCurrentPlanIsUnavailable() {
        let currentPlans = CodexPlanCatalog.plans.filter {
            CodexPlanCatalog.isCurrent($0, currentPlanName: nil)
        }

        XCTAssertEqual(currentPlans.map(\.name), ["Free"])
    }

    func testMenuStaleAvailabilityDescribesDataRefreshWithoutImplyingPlanExpiry() {
        let state = DashboardLoadState.stale(
            .fixture(todayTokens: 17),
            .fixture,
            "暂时无法刷新，正在显示上次可用数据。"
        )

        let text = MenuBarAvailabilityText.text(for: state)

        XCTAssertEqual(text, "数据待更新")
        XCTAssertFalse(text.contains("过期"))
    }

    func testRefreshPublishesRealSnapshotAndCoalescesConcurrentCalls() async {
        let client = FakeDashboardDataClient(
            loadResult: .empty(.fixture),
            refreshResults: [.loaded(.fixture(todayTokens: 42), .fixture)],
            pauseRefresh: true
        )
        let store = DashboardStore(client: client, refreshInterval: .seconds(60))

        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        await eventually { await client.refreshCount == 1 }
        await client.resumeRefresh()
        _ = await (first, second)

        guard case let .loaded(snapshot, _) = store.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertEqual(snapshot.todayTokens, 42)
        let refreshCount = await client.refreshCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertFalse(store.isRefreshing)
    }

    func testNoCodexDataPublishesEmptyInsteadOfPreview() async {
        let client = FakeDashboardDataClient(
            loadResult: .empty(.fixture),
            refreshResults: [.empty(.fixture)]
        )
        let store = DashboardStore(client: client, refreshInterval: .seconds(60))

        await store.refresh()

        guard case .empty = store.state else { return XCTFail("Expected empty state") }
    }

    func testRefreshFailureKeepsLastUsableSnapshotWithSafeMessage() async {
        let cached = DashboardSnapshot.fixture(todayTokens: 17)
        let client = FakeDashboardDataClient(
            loadResult: .loaded(cached, .fixture),
            refreshResults: [],
            refreshFailure: .fixture
        )
        let store = DashboardStore(client: client, refreshInterval: .seconds(60))

        await store.loadCached()
        await store.refresh()

        guard case let .stale(snapshot, _, message) = store.state else {
            return XCTFail("Expected stale state")
        }
        XCTAssertEqual(snapshot.todayTokens, 17)
        XCTAssertEqual(message, "暂时无法刷新，正在显示上次可用数据。")
        XCTAssertFalse(message.contains("fixture-secret"))
    }

    func testStartIsIdempotentAndOwnsSingleBackfillAndAutomaticLoop() async {
        let sleeper = SuspendedSleeper()
        let client = FakeDashboardDataClient(
            loadResult: .loaded(.fixture(todayTokens: 1), .fixture),
            refreshResults: [.loaded(.fixture(todayTokens: 2), .fixture)],
            backfillResult: .loaded(.fixture(todayTokens: 3), .fixture)
        )
        let store = DashboardStore(
            client: client,
            refreshInterval: .seconds(60),
            sleeper: { duration in try await sleeper.sleep(for: duration) }
        )

        async let first: Void = store.start()
        async let second: Void = store.start()
        _ = await (first, second)
        await eventually {
            let backfillCount = await client.backfillCount
            let sleepCount = await sleeper.callCount
            return backfillCount == 1 && sleepCount == 1
        }

        let loadCachedCount = await client.loadCachedCount
        let refreshCount = await client.refreshCount
        let backfillCount = await client.backfillCount
        let sleepCount = await sleeper.callCount
        XCTAssertEqual(loadCachedCount, 1)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(backfillCount, 1)
        XCTAssertEqual(sleepCount, 1)
    }

    func testOlderBackfillResultDoesNotOverwriteNewerForegroundRefresh() async {
        let sleeper = SuspendedSleeper()
        let client = FakeDashboardDataClient(
            loadResult: .loaded(.fixture(todayTokens: 1), .fixture),
            refreshResults: [
                .loaded(.fixture(todayTokens: 2), .fixture),
                .loaded(.fixture(todayTokens: 9), .fixture)
            ],
            backfillResult: .loaded(.fixture(todayTokens: 3), .fixture),
            pauseBackfill: true
        )
        let store = DashboardStore(
            client: client,
            refreshInterval: .seconds(60),
            sleeper: { duration in try await sleeper.sleep(for: duration) }
        )

        await store.start()
        await eventually { await client.backfillCount == 1 }
        await store.refresh()
        await client.resumeBackfill()
        await eventually { await client.completedBackfillCount == 1 }

        guard case let .loaded(snapshot, _) = store.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertEqual(snapshot.todayTokens, 9)
    }

    func testAutomaticLoopDoesNotKeepStoreAliveAndIsCancelledOnTeardown() async {
        let sleeper = SuspendedSleeper()
        let client = FakeDashboardDataClient(
            loadResult: .empty(.fixture),
            refreshResults: [.empty(.fixture)],
            backfillResult: .empty(.fixture)
        )
        var store: DashboardStore? = DashboardStore(
            client: client,
            refreshInterval: .seconds(60),
            sleeper: { duration in try await sleeper.sleep(for: duration) }
        )
        weak let weakStore = store

        await store?.start()
        await eventually { await sleeper.callCount == 1 }
        store = nil
        await eventually {
            let cancellationCount = await sleeper.cancellationCount
            return weakStore == nil && cancellationCount == 1
        }

        XCTAssertNil(weakStore)
        let cancellationCount = await sleeper.cancellationCount
        XCTAssertEqual(cancellationCount, 1)
    }

    func testLiveClientUsesInjectedTemporaryLocationsAndCachedLoadDoesNotImport() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardStoreTests-\(UUID().uuidString)", isDirectory: true)
        let codexRoot = directory.appendingPathComponent("synthetic-codex", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("synthetic-app-support/SpendScope.sqlite")
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = try LiveDashboardDataClient(
            codexRootURL: codexRoot,
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1_000) },
            calendar: .fixture
        )

        let cached = try await client.loadCached()

        guard case let .empty(summary) = cached else { return XCTFail("Expected empty cache") }
        XCTAssertEqual(summary.cli, .missing)
        XCTAssertEqual(summary.desktop, .missing)
        XCTAssertEqual(summary.index, .missing)
        XCTAssertNil(summary.lastSuccessfulRefresh)
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testLiveClientDoesNotEnterCachedQueryWhileImporterAwaitOwnsSharedConnection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardStoreGateTests-\(UUID().uuidString)", isDirectory: true)
        let codexRoot = directory.appendingPathComponent("synthetic-codex", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("synthetic-app-support/SpendScope.sqlite")
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = LiveSerializationProbe()
        let client = try LiveDashboardDataClient(
            codexRootURL: codexRoot,
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1_000) },
            calendar: .fixture,
            beforeImport: { scope in await probe.pauseForegroundImport(scope) },
            beforeQuery: { await probe.recordQueryEntry() }
        )

        async let refreshResult = client.refresh()
        await eventually { await probe.foregroundImportIsPaused }
        async let cachedResult = client.loadCached()
        for _ in 0..<100 { await Task.yield() }

        let queriesBeforeRelease = await probe.queryEntryCount
        XCTAssertEqual(queriesBeforeRelease, 0)
        await probe.resumeForegroundImport()
        _ = try await (refreshResult, cachedResult)
        let finalQueryCount = await probe.queryEntryCount
        XCTAssertEqual(finalQueryCount, 2)
    }

    func testCancellingQueuedCachedLoadFinishesBeforeForegroundHolderIsReleased() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardStoreGateCancellation-\(UUID().uuidString)", isDirectory: true)
        let codexRoot = directory.appendingPathComponent("synthetic-codex", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("synthetic-app-support/SpendScope.sqlite")
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = LiveSerializationProbe()
        let client = try LiveDashboardDataClient(
            codexRootURL: codexRoot,
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1_000) },
            calendar: .fixture,
            beforeImport: { scope in await probe.pauseForegroundImport(scope) },
            beforeQuery: { await probe.recordQueryEntry() }
        )
        let holder = Task { try await client.refresh() }
        await eventually { await probe.foregroundImportIsPaused }
        let queued = Task { () -> Error? in
            do {
                _ = try await client.loadCached()
                return nil
            } catch {
                return error
            }
        }
        for _ in 0..<100 { await Task.yield() }
        let queuedFinished = expectation(description: "cancelled gate waiter finishes")
        Task {
            _ = await queued.value
            queuedFinished.fulfill()
        }

        queued.cancel()
        await fulfillment(of: [queuedFinished], timeout: 0.2)

        let cancellationError = await queued.value
        XCTAssertTrue(cancellationError is CancellationError)
        let queryEntryCount = await probe.queryEntryCount
        XCTAssertEqual(queryEntryCount, 0)
        await probe.resumeForegroundImport()
        _ = try await holder.value
    }

    func testCachedZeroUsageWithPersistedCurrentMalformedFileFailsInsteadOfEmpty() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardStoreCachedHealth-\(UUID().uuidString)", isDirectory: true)
        let codexRoot = directory.appendingPathComponent("synthetic-codex", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("synthetic-app-support/SpendScope.sqlite")
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try UsageStore(databaseURL: databaseURL)
        try store.commit(ImportBatch(
            file: FileCheckpoint(
                fileID: "current-bad", deviceID: 1, inode: 1,
                path: "/synthetic/current-bad.jsonl", fileSize: 10, committedOffset: 0,
                generation: 0, threadID: nil, lastRecordAtMilliseconds: 1_000,
                lastSuccessAtMilliseconds: nil, formatStatus: "error",
                lastError: "malformed-event"
            ),
            usageEvents: [], quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
        ))
        try store.persistSourceStatus(
            indexHealth: .missing,
            discoveredFileIDs: ["current-bad"],
            issues: [],
            processedFileCount: 1
        )
        let client = try LiveDashboardDataClient(
            codexRootURL: codexRoot,
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1_000) },
            calendar: .fixture
        )

        do {
            _ = try await client.loadCached()
            XCTFail("Expected persisted malformed current file to block empty state")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testCachedUsageWithPersistedDegradedIndexIsStaleButMissingIndexIsLoaded() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardStoreCachedIndexHealth-\(UUID().uuidString)", isDirectory: true)
        let codexRoot = directory.appendingPathComponent("synthetic-codex", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("synthetic-app-support/SpendScope.sqlite")
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try UsageStore(databaseURL: databaseURL)
        try store.commit(ImportBatch(
            file: FileCheckpoint(
                fileID: "cached-usage", deviceID: 1, inode: 1,
                path: "/synthetic/cached-usage.jsonl", fileSize: 10, committedOffset: 10,
                generation: 0, threadID: "cached-thread", lastRecordAtMilliseconds: 1_000,
                lastSuccessAtMilliseconds: 1_000, formatStatus: "supported", lastError: nil
            ),
            usageEvents: [StoredUsageEvent(
                fingerprint: "cached-index-usage", observedAtMilliseconds: 1_000,
                threadID: "cached-thread", sourceKind: .cli, model: "test-model",
                plan: PlanResolver.resolve(rawValue: "plus"),
                usage: TokenUsageDelta(
                    uncachedInput: 42, cachedInput: 0, visibleOutput: 0, reasoning: 0
                ),
                sourceFileID: "cached-usage", sourceOffset: 10
            )],
            quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
        ))
        try store.persistSourceStatus(
            indexHealth: .degraded("sensitive"),
            discoveredFileIDs: ["cached-usage"],
            issues: [],
            processedFileCount: 1
        )

        let degradedClient = try LiveDashboardDataClient(
            codexRootURL: codexRoot,
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1_000) },
            calendar: .fixture
        )
        guard case .stale = try await degradedClient.loadCached() else {
            return XCTFail("Expected persisted degraded index to make cached usage stale")
        }

        try store.persistSourceStatus(
            indexHealth: .missing,
            discoveredFileIDs: ["cached-usage"],
            issues: [],
            processedFileCount: 0
        )
        let missingClient = try LiveDashboardDataClient(
            codexRootURL: codexRoot,
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1_000) },
            calendar: .fixture
        )
        guard case .loaded = try await missingClient.loadCached() else {
            return XCTFail("A missing index alone must not make cached usage stale")
        }
    }

    func testCachedCurrentReadFailureWithoutCheckpointSurvivesRestartAndFailsSafely() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardStoreCachedReadHealth-\(UUID().uuidString)", isDirectory: true)
        let codexRoot = directory.appendingPathComponent("synthetic-codex", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("synthetic-app-support/SpendScope.sqlite")
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try UsageStore(databaseURL: databaseURL)
        try store.persistSourceStatus(
            indexHealth: .missing,
            discoveredFileIDs: ["unread-current"],
            issues: [.init(kind: .read, fileID: "unread-current", detail: "raw-sensitive")],
            processedFileCount: 0
        )
        XCTAssertTrue(try UsageStore(databaseURL: databaseURL).sourceFacts().hasDegradedFiles)

        let client = try LiveDashboardDataClient(
            codexRootURL: codexRoot,
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1_000) },
            calendar: .fixture
        )
        do {
            _ = try await client.loadCached()
            XCTFail("Expected persisted current read failure to block an empty dashboard")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    private func eventually(
        _ condition: @escaping @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not met", file: file, line: line)
    }
}

private enum FakeClientError: Error, Sendable {
    case fixture

    var sensitiveText: String { "fixture-secret" }
}

private actor FakeDashboardDataClient: DashboardDataClient {
    private let loadResult: DashboardDataResult
    private var refreshResults: [DashboardDataResult]
    private let backfillResult: DashboardDataResult
    private let refreshFailure: FakeClientError?
    private let pauseRefresh: Bool
    private let pauseBackfill: Bool
    private var refreshContinuations: [CheckedContinuation<Void, Never>] = []
    private var backfillContinuations: [CheckedContinuation<Void, Never>] = []

    private(set) var loadCachedCount = 0
    private(set) var refreshCount = 0
    private(set) var backfillCount = 0
    private(set) var completedBackfillCount = 0

    init(
        loadResult: DashboardDataResult,
        refreshResults: [DashboardDataResult],
        backfillResult: DashboardDataResult = .empty(.fixture),
        refreshFailure: FakeClientError? = nil,
        pauseRefresh: Bool = false,
        pauseBackfill: Bool = false
    ) {
        self.loadResult = loadResult
        self.refreshResults = refreshResults
        self.backfillResult = backfillResult
        self.refreshFailure = refreshFailure
        self.pauseRefresh = pauseRefresh
        self.pauseBackfill = pauseBackfill
    }

    func loadCached() async throws -> DashboardDataResult {
        loadCachedCount += 1
        return loadResult
    }

    func refresh() async throws -> DashboardDataResult {
        refreshCount += 1
        if pauseRefresh {
            await withCheckedContinuation { refreshContinuations.append($0) }
        }
        if let refreshFailure { throw refreshFailure }
        return refreshResults.removeFirst()
    }

    func backfillHistory() async throws -> DashboardDataResult {
        backfillCount += 1
        if pauseBackfill {
            await withCheckedContinuation { backfillContinuations.append($0) }
        }
        completedBackfillCount += 1
        return backfillResult
    }

    func resumeRefresh() {
        refreshContinuations.forEach { $0.resume() }
        refreshContinuations.removeAll()
    }

    func resumeBackfill() {
        backfillContinuations.forEach { $0.resume() }
        backfillContinuations.removeAll()
    }
}

private actor SuspendedSleeper {
    private var continuations: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private(set) var callCount = 0
    private(set) var cancellationCount = 0

    func sleep(for duration: Duration) async throws {
        _ = duration
        let id = UUID()
        callCount += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[id] = continuation
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    private func cancel(id: UUID) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        cancellationCount += 1
        continuation.resume(throwing: CancellationError())
    }
}

private actor LiveSerializationProbe {
    private var foregroundContinuation: CheckedContinuation<Void, Never>?
    private(set) var foregroundImportIsPaused = false
    private(set) var queryEntryCount = 0

    func pauseForegroundImport(_ scope: ImportScope) async {
        guard scope == .foreground else { return }
        foregroundImportIsPaused = true
        await withCheckedContinuation { foregroundContinuation = $0 }
    }

    func recordQueryEntry() {
        queryEntryCount += 1
    }

    func resumeForegroundImport() {
        foregroundContinuation?.resume()
        foregroundContinuation = nil
    }
}

private extension SourceSummary {
    static let fixture = SourceSummary(
        cli: .connected,
        desktop: .connected,
        index: .connected,
        lastSuccessfulRefresh: Date(timeIntervalSince1970: 1)
    )
}

private extension DashboardSnapshot {
    static func fixture(todayTokens: Int) -> DashboardSnapshot {
        DashboardSnapshot(
            planName: "Plus",
            updatedText: "已刷新",
            periods: [
                .init(
                    id: "today", title: "今日", total: todayTokens,
                    uncachedInput: todayTokens, cachedInput: 0, output: 0, reasoning: 0
                ),
                .init(
                    id: "sevenDays", title: "7 日", total: todayTokens,
                    uncachedInput: todayTokens, cachedInput: 0, output: 0, reasoning: 0
                ),
                .init(
                    id: "thirtyDays", title: "30 日", total: todayTokens,
                    uncachedInput: todayTokens, cachedInput: 0, output: 0, reasoning: 0
                ),
                .init(
                    id: "allTime", title: "累计", total: todayTokens,
                    uncachedInput: todayTokens, cachedInput: 0, output: 0, reasoning: 0
                )
            ],
            quotas: [], models: [], dailyUsage: []
        )
    }
}

private extension Calendar {
    static var fixture: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
