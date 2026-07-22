import Foundation
import XCTest
@testable import SpendScope

@MainActor
final class DashboardStoreTests: XCTestCase {
    func testCodexPlanCatalogIncludesCurrentOfficialPlansAndMarksProCurrent() {
        XCTAssertEqual(
            CodexPlanCatalog.plans.map(\.name),
            ["Free", "Go", "Plus", "Pro 5x", "Pro 20x", "Business", "Enterprise / Edu"]
        )
        XCTAssertFalse(CodexPlanCatalog.plans[0].isPaid)
        XCTAssertTrue(CodexPlanCatalog.plans.dropFirst().allSatisfy(\.isPaid))

        let currentPlans = CodexPlanCatalog.plans.filter {
            CodexPlanCatalog.isCurrent($0, currentPlanName: "Pro 5x")
        }

        XCTAssertEqual(currentPlans.map(\.name), ["Pro 5x"])
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

    func testMenuUpdateTextCombinesStaleStateWithLastRefresh() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let state = DashboardLoadState.stale(
            .fixture(todayTokens: 17),
            .fixture,
            "部分数据暂不可用，正在显示已成功读取的数据。"
        )

        XCTAssertEqual(
            MenuBarUpdateText.text(for: state, calendar: calendar),
            "部分数据待更新 · 已刷新 · 00:00"
        )
    }

    func testMenuUpdateTextUsesUpdateCopyAndTwentyFourHourRefreshTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .gmt
        let state = DashboardLoadState.loaded(
            .fixture(todayTokens: 17, updatedText: "刚刚刷新"),
            SourceSummary(
                cli: .connected,
                desktop: .connected,
                index: .connected,
                lastSuccessfulRefresh: Date(timeIntervalSince1970: 3_661)
            )
        )

        XCTAssertEqual(
            MenuBarUpdateText.text(for: state, calendar: calendar),
            "刚刚更新 · 09:01"
        )
    }

    func testMenuUnavailableContentReplacesMetricsForNonUsableStates() throws {
        let failed = try XCTUnwrap(MenuBarUnavailableContent.content(for: .failed("读取失败")))

        XCTAssertEqual(failed.title, "暂时无法读取数据")
        XCTAssertEqual(failed.description, "读取失败")
        XCTAssertTrue(failed.showsRefresh)
        XCTAssertNil(MenuBarUnavailableContent.content(for: .loaded(.fixture(todayTokens: 1), .fixture)))
        XCTAssertNil(MenuBarUnavailableContent.content(for: .stale(
            .fixture(todayTokens: 1),
            .fixture,
            "部分数据待更新"
        )))
    }

    func testRefreshPublishesRealSnapshotAndCoalescesConcurrentCalls() async {
        let client = FakeDashboardDataClient(
            loadResult: .empty(.fixture),
            refreshResults: [.loaded(.fixture(todayTokens: 42), .fixture)],
            pauseRefresh: true
        )
        let store = DashboardStore(client: client, usageRefreshInterval: .seconds(60))

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
        let quotaRefreshCount = await client.quotaRefreshCount
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(quotaRefreshCount, 1)
        XCTAssertFalse(store.isRefreshing)
    }

    func testRebuildCoalescesRequestsAndReplacesVisibleData() async {
        let client = FakeDashboardDataClient(
            loadResult: .loaded(.fixture(todayTokens: 17), .fixture),
            refreshResults: [],
            rebuildResult: .loaded(.fixture(todayTokens: 84), .fixture),
            pauseRebuild: true
        )
        let store = DashboardStore(client: client, usageRefreshInterval: .seconds(60))
        await store.loadCached()

        async let first: Void = store.rebuildFromLocalData()
        async let second: Void = store.rebuildFromLocalData()
        await eventually { await client.rebuildCount == 1 }

        XCTAssertTrue(store.isRebuildingData)
        XCTAssertNil(store.snapshot)
        guard case .loading = store.state else { return XCTFail("Expected loading state") }

        await client.resumeRebuild()
        _ = await (first, second)

        guard case let .loaded(snapshot, _) = store.state else {
            return XCTFail("Expected rebuilt state")
        }
        XCTAssertEqual(snapshot.todayTokens, 84)
        let rebuildCount = await client.rebuildCount
        XCTAssertEqual(rebuildCount, 1)
        XCTAssertFalse(store.isRebuildingData)
    }

    func testNoCodexDataPublishesEmptyInsteadOfPreview() async {
        let client = FakeDashboardDataClient(
            loadResult: .empty(.fixture),
            refreshResults: [.empty(.fixture)]
        )
        let store = DashboardStore(client: client, usageRefreshInterval: .seconds(60))

        await store.refresh()

        guard case .empty = store.state else { return XCTFail("Expected empty state") }
    }

    func testRefreshFailureKeepsLastUsableSnapshotWithSafeMessage() async {
        let cached = DashboardSnapshot.fixture(todayTokens: 17)
        let client = FakeDashboardDataClient(
            loadResult: .loaded(cached, .fixture),
            refreshResults: [],
            refreshFailure: .fixture,
            quotaFailure: .fixture
        )
        let store = DashboardStore(client: client, usageRefreshInterval: .seconds(60))

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
            usageRefreshInterval: .seconds(60),
            sleeper: { duration in try await sleeper.sleep(for: duration) }
        )

        async let first: Void = store.start()
        async let second: Void = store.start()
        _ = await (first, second)
        await eventually {
            let backfillCount = await client.backfillCount
            let sleepCount = await sleeper.callCount
            return backfillCount == 1 && sleepCount == 2
        }

        let loadCachedCount = await client.loadCachedCount
        let refreshCount = await client.refreshCount
        let quotaRefreshCount = await client.quotaRefreshCount
        let backfillCount = await client.backfillCount
        let sleepCount = await sleeper.callCount
        let requestedDurations = await sleeper.requestedDurations
        XCTAssertEqual(loadCachedCount, 1)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(quotaRefreshCount, 1)
        XCTAssertEqual(backfillCount, 1)
        XCTAssertEqual(sleepCount, 2)
        XCTAssertTrue(requestedDurations.contains(.seconds(60)))
        XCTAssertTrue(requestedDurations.contains(.seconds(120)))
    }

    func testStartWithAutomaticRefreshDisabledStillLoadsWithoutLaunchingLoop() async {
        let sleeper = SuspendedSleeper()
        let client = FakeDashboardDataClient(
            loadResult: .loaded(.fixture(todayTokens: 1), .fixture),
            refreshResults: [.loaded(.fixture(todayTokens: 2), .fixture)],
            backfillResult: .loaded(.fixture(todayTokens: 3), .fixture)
        )
        let store = DashboardStore(
            client: client,
            usageRefreshInterval: .seconds(60),
            automaticRefreshEnabled: false,
            sleeper: { duration in try await sleeper.sleep(for: duration) }
        )

        await store.start()
        await eventually { await client.backfillCount == 1 }

        let loadCachedCount = await client.loadCachedCount
        let refreshCount = await client.refreshCount
        let quotaRefreshCount = await client.quotaRefreshCount
        let sleepCount = await sleeper.callCount
        XCTAssertFalse(store.isAutomaticRefreshEnabled)
        XCTAssertEqual(loadCachedCount, 1)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(quotaRefreshCount, 1)
        XCTAssertEqual(sleepCount, 0)
    }

    func testAutomaticRefreshCanBeStoppedAndRestarted() async {
        let sleeper = SuspendedSleeper()
        let client = FakeDashboardDataClient(
            loadResult: .empty(.fixture),
            refreshResults: [.empty(.fixture)],
            backfillResult: .empty(.fixture)
        )
        let store = DashboardStore(
            client: client,
            usageRefreshInterval: .seconds(60),
            sleeper: { duration in try await sleeper.sleep(for: duration) }
        )

        await store.start()
        await eventually { await sleeper.callCount == 2 }

        store.setAutomaticRefreshEnabled(false)
        await eventually { await sleeper.cancellationCount == 2 }
        XCTAssertFalse(store.isAutomaticRefreshEnabled)

        store.setAutomaticRefreshEnabled(true)
        await eventually { await sleeper.callCount == 4 }
        XCTAssertTrue(store.isAutomaticRefreshEnabled)
    }

    func testQuotaRefreshRunsOncePerNeedAndSkipsWhenUsageIsUnchanged() async {
        let tenTokens = DashboardSnapshot.fixture(todayTokens: 10)
        let elevenTokens = DashboardSnapshot.fixture(todayTokens: 11)
        let client = FakeDashboardDataClient(
            loadResult: .loaded(tenTokens, .fixture),
            refreshResults: [
                .loaded(tenTokens, .fixture),
                .loaded(elevenTokens, .fixture)
            ],
            quotaResults: [
                .loaded(tenTokens, .fixture),
                .loaded(elevenTokens, .fixture)
            ]
        )
        let store = DashboardStore(client: client, automaticRefreshEnabled: false)

        await store.loadCached()
        await store.refreshQuotaIfNeeded()
        await store.refreshQuotaIfNeeded()
        var quotaRefreshCount = await client.quotaRefreshCount
        XCTAssertEqual(quotaRefreshCount, 1)

        await store.refreshUsage()
        await store.refreshQuotaIfNeeded()
        quotaRefreshCount = await client.quotaRefreshCount
        XCTAssertEqual(quotaRefreshCount, 1)

        await store.refreshUsage()
        await store.refreshQuotaIfNeeded()
        await store.refreshQuotaIfNeeded()
        quotaRefreshCount = await client.quotaRefreshCount
        XCTAssertEqual(quotaRefreshCount, 2)
    }

    func testManualRefreshAlwaysRefreshesQuotaAndConsumesPendingNeed() async {
        let snapshot = DashboardSnapshot.fixture(todayTokens: 10)
        let client = FakeDashboardDataClient(
            loadResult: .loaded(snapshot, .fixture),
            refreshResults: [
                .loaded(snapshot, .fixture),
                .loaded(snapshot, .fixture)
            ]
        )
        let store = DashboardStore(client: client, automaticRefreshEnabled: false)

        await store.loadCached()
        await store.refreshQuotaIfNeeded()
        await store.refresh()
        await store.refresh()
        await store.refreshQuotaIfNeeded()

        let usageRefreshCount = await client.refreshCount
        let quotaRefreshCount = await client.quotaRefreshCount
        XCTAssertEqual(usageRefreshCount, 2)
        XCTAssertEqual(quotaRefreshCount, 3)
    }

    func testFailedQuotaRefreshRemainsNeededForNextCheck() async {
        let snapshot = DashboardSnapshot.fixture(todayTokens: 10)
        let client = FakeDashboardDataClient(
            loadResult: .loaded(snapshot, .fixture),
            refreshResults: [],
            quotaFailure: .fixture
        )
        let store = DashboardStore(client: client, automaticRefreshEnabled: false)

        await store.loadCached()
        await store.refreshQuotaIfNeeded()
        await store.refreshQuotaIfNeeded()

        let quotaRefreshCount = await client.quotaRefreshCount
        XCTAssertEqual(quotaRefreshCount, 2)
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
            usageRefreshInterval: .seconds(60),
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
            usageRefreshInterval: .seconds(60),
            sleeper: { duration in try await sleeper.sleep(for: duration) }
        )
        weak let weakStore = store

        await store?.start()
        await eventually { await sleeper.callCount == 2 }
        store = nil
        await eventually {
            let cancellationCount = await sleeper.cancellationCount
            return weakStore == nil && cancellationCount == 2
        }

        XCTAssertNil(weakStore)
        let cancellationCount = await sleeper.cancellationCount
        XCTAssertEqual(cancellationCount, 2)
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

    func testLiveClientRefreshesOfficialQuotaOnlyThroughQuotaOperation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardStoreQuotaTests-\(UUID().uuidString)", isDirectory: true)
        let codexRoot = directory.appendingPathComponent("synthetic-codex", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("synthetic-app-support/SpendScope.sqlite")
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = try UsageStore(databaseURL: databaseURL)
        try storage.commit(ImportBatch(
            file: FileCheckpoint(
                fileID: "quota-source", deviceID: 1, inode: 1,
                path: "/synthetic/quota.jsonl", fileSize: 10, committedOffset: 10,
                generation: 0, threadID: "thread-1", lastRecordAtMilliseconds: 999_000,
                lastSuccessAtMilliseconds: 999_000, formatStatus: "supported", lastError: nil
            ),
            usageEvents: [StoredUsageEvent(
                fingerprint: "usage", observedAtMilliseconds: 999_000,
                threadID: "thread-1", sourceKind: .cli, model: "test-model",
                plan: PlanResolver.resolve(rawValue: "plus"),
                usage: TokenUsageDelta(
                    uncachedInput: 10, cachedInput: 0, visibleOutput: 0, reasoning: 0
                ),
                sourceFileID: "quota-source", sourceOffset: 10
            )],
            quotaEvents: [StoredQuotaEvent(
                fingerprint: "stored-100-percent", threadID: "thread-1",
                observation: QuotaObservation(
                    kind: .weekly, observedAtMilliseconds: 999_000,
                    windowMinutes: 10_080, remaining: 1,
                    resetsAtMilliseconds: 2_000_000,
                    plan: PlanResolver.resolve(rawValue: "plus")
                ),
                sourceKind: .cli
            )],
            stateEvents: [], sessions: [], threadCheckpoints: []
        ))
        let accountRateLimits = CodexAccountRateLimits(
            planRaw: "prolite",
            windows: [RawQuotaWindow(
                windowMinutes: 10_080,
                usedPercent: 3,
                resetsAtSeconds: 2_000
            )],
            observedAt: Date(timeIntervalSince1970: 1_000)
        )
        let rateLimitReader = CountingAccountRateLimitReader(value: accountRateLimits)
        let client = try LiveDashboardDataClient(
            codexRootURL: codexRoot,
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1_000) },
            calendar: .fixture,
            accountRateLimitReader: rateLimitReader
        )

        guard case let .loaded(usageSnapshot, _) = try await client.refreshUsage() else {
            return XCTFail("Expected loaded usage dashboard")
        }
        XCTAssertEqual(usageSnapshot.weeklyQuota?.remaining ?? -1, 1, accuracy: 0.000_001)
        let readCountBeforeQuotaRefresh = await rateLimitReader.readCount
        XCTAssertEqual(readCountBeforeQuotaRefresh, 0)

        let result = try await client.refreshQuota()

        guard case let .loaded(snapshot, _) = result else {
            return XCTFail("Expected loaded dashboard")
        }
        XCTAssertEqual(snapshot.planName, "Pro 5x")
        XCTAssertEqual(snapshot.weeklyQuota?.remaining ?? -1, 0.97, accuracy: 0.000_001)
        let readCountAfterQuotaRefresh = await rateLimitReader.readCount
        XCTAssertEqual(readCountAfterQuotaRefresh, 1)
        XCTAssertEqual(try storage.accountRateLimits(), accountRateLimits)

        let offlineClient = try LiveDashboardDataClient(
            codexRootURL: codexRoot,
            databaseURL: databaseURL,
            now: { Date(timeIntervalSince1970: 1_000) },
            calendar: .fixture,
            accountRateLimitReader: FailingAccountRateLimitReader()
        )
        guard case let .loaded(cachedSnapshot, _) = try await offlineClient.loadCached() else {
            return XCTFail("Expected cached dashboard after restart")
        }
        XCTAssertEqual(cachedSnapshot.planName, "Pro 5x")
        XCTAssertEqual(cachedSnapshot.weeklyQuota?.remaining ?? -1, 0.97, accuracy: 0.000_001)

        guard case let .loaded(offlineSnapshot, _) = try await offlineClient.refreshUsage() else {
            return XCTFail("Expected cached official quota when live refresh fails")
        }
        XCTAssertEqual(offlineSnapshot.weeklyQuota?.remaining ?? -1, 0.97, accuracy: 0.000_001)
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

        async let refreshResult = client.refreshUsage()
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
        let holder = Task { try await client.refreshUsage() }
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

private actor CountingAccountRateLimitReader: CodexAccountRateLimitReading {
    let value: CodexAccountRateLimits
    private(set) var readCount = 0

    init(value: CodexAccountRateLimits) {
        self.value = value
    }

    func read() async throws -> CodexAccountRateLimits {
        readCount += 1
        return value
    }
}

private struct FailingAccountRateLimitReader: CodexAccountRateLimitReading {
    func read() async throws -> CodexAccountRateLimits { throw FakeClientError.fixture }
}

private actor FakeDashboardDataClient: DashboardDataClient {
    private let loadResult: DashboardDataResult
    private var currentResult: DashboardDataResult
    private var refreshResults: [DashboardDataResult]
    private var quotaResults: [DashboardDataResult]
    private let backfillResult: DashboardDataResult
    private let rebuildResult: DashboardDataResult
    private let refreshFailure: FakeClientError?
    private let quotaFailure: FakeClientError?
    private let pauseRefresh: Bool
    private let pauseBackfill: Bool
    private let pauseRebuild: Bool
    private var refreshContinuations: [CheckedContinuation<Void, Never>] = []
    private var backfillContinuations: [CheckedContinuation<Void, Never>] = []
    private var rebuildContinuations: [CheckedContinuation<Void, Never>] = []

    private(set) var loadCachedCount = 0
    private(set) var refreshCount = 0
    private(set) var quotaRefreshCount = 0
    private(set) var backfillCount = 0
    private(set) var completedBackfillCount = 0
    private(set) var rebuildCount = 0

    init(
        loadResult: DashboardDataResult,
        refreshResults: [DashboardDataResult],
        quotaResults: [DashboardDataResult] = [],
        backfillResult: DashboardDataResult = .empty(.fixture),
        rebuildResult: DashboardDataResult = .empty(.fixture),
        refreshFailure: FakeClientError? = nil,
        quotaFailure: FakeClientError? = nil,
        pauseRefresh: Bool = false,
        pauseBackfill: Bool = false,
        pauseRebuild: Bool = false
    ) {
        self.loadResult = loadResult
        currentResult = loadResult
        self.refreshResults = refreshResults
        self.quotaResults = quotaResults
        self.backfillResult = backfillResult
        self.rebuildResult = rebuildResult
        self.refreshFailure = refreshFailure
        self.quotaFailure = quotaFailure
        self.pauseRefresh = pauseRefresh
        self.pauseBackfill = pauseBackfill
        self.pauseRebuild = pauseRebuild
    }

    func loadCached() async throws -> DashboardDataResult {
        loadCachedCount += 1
        currentResult = loadResult
        return loadResult
    }

    func refreshUsage() async throws -> DashboardDataResult {
        refreshCount += 1
        if pauseRefresh {
            await withCheckedContinuation { refreshContinuations.append($0) }
        }
        if let refreshFailure { throw refreshFailure }
        let result = refreshResults.removeFirst()
        currentResult = result
        return result
    }

    func refreshQuota() async throws -> DashboardDataResult {
        quotaRefreshCount += 1
        if let quotaFailure { throw quotaFailure }
        let result = quotaResults.isEmpty ? currentResult : quotaResults.removeFirst()
        currentResult = result
        return result
    }

    func backfillHistory() async throws -> DashboardDataResult {
        backfillCount += 1
        if pauseBackfill {
            await withCheckedContinuation { backfillContinuations.append($0) }
        }
        completedBackfillCount += 1
        currentResult = backfillResult
        return backfillResult
    }

    func rebuildFromLocalData() async throws -> DashboardDataResult {
        rebuildCount += 1
        if pauseRebuild {
            await withCheckedContinuation { rebuildContinuations.append($0) }
        }
        currentResult = rebuildResult
        return rebuildResult
    }

    func resumeRefresh() {
        refreshContinuations.forEach { $0.resume() }
        refreshContinuations.removeAll()
    }

    func resumeBackfill() {
        backfillContinuations.forEach { $0.resume() }
        backfillContinuations.removeAll()
    }

    func resumeRebuild() {
        rebuildContinuations.forEach { $0.resume() }
        rebuildContinuations.removeAll()
    }
}

private actor SuspendedSleeper {
    private var continuations: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private(set) var callCount = 0
    private(set) var cancellationCount = 0
    private(set) var requestedDurations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        callCount += 1
        requestedDurations.append(duration)
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
    static func fixture(todayTokens: Int, updatedText: String = "已刷新") -> DashboardSnapshot {
        DashboardSnapshot(
            planName: "Plus",
            updatedText: updatedText,
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
