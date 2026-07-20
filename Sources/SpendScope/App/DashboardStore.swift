import Foundation
import Observation
import OSLog

private let quotaLogger = Logger(subsystem: "com.ychp.SpendScope", category: "quota")

enum DashboardLoadState: Sendable {
    case loading
    case loaded(DashboardSnapshot, SourceSummary)
    case empty(SourceSummary)
    case stale(DashboardSnapshot, SourceSummary, String)
    case failed(String)
    case unsupported(String)
}

enum SourceHealth: String, Sendable {
    case connected
    case missing
    case degraded
    case unsupported
}

struct SourceSummary: Sendable {
    let cli: SourceHealth
    let desktop: SourceHealth
    let index: SourceHealth
    let lastSuccessfulRefresh: Date?
}

enum DashboardDataResult: Sendable {
    case loaded(DashboardSnapshot, SourceSummary)
    case empty(SourceSummary)
    case stale(DashboardSnapshot, SourceSummary, String)
    case unsupported(String)
}

protocol DashboardDataClient: Sendable {
    func loadCached() async throws -> DashboardDataResult
    func refreshUsage() async throws -> DashboardDataResult
    func refreshQuota() async throws -> DashboardDataResult
    func backfillHistory() async throws -> DashboardDataResult
    func rebuildFromLocalData() async throws -> DashboardDataResult
}

actor LiveDashboardDataClient: DashboardDataClient {
    private let store: UsageStore
    private let importer: CodexImporter
    private let queryService: DashboardQueryService
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let usageCalendar: Calendar
    private let accountRateLimitReader: (any CodexAccountRateLimitReading)?
    private let beforeImport: @Sendable (ImportScope) async -> Void
    private let beforeQuery: @Sendable () async -> Void
    private var operationIsRunning = false
    private var operationWaiters: [OperationWaiter] = []

    init(
        codexRootURL: URL,
        databaseURL: URL,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current,
        usageCalendar: Calendar = CodexUsageCalendar.utc,
        fileManager: FileManager = .default,
        accountRateLimitReader: (any CodexAccountRateLimitReading)? = nil,
        beforeImport: @escaping @Sendable (ImportScope) async -> Void = { _ in },
        beforeQuery: @escaping @Sendable () async -> Void = {}
    ) throws {
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let store = try UsageStore(databaseURL: databaseURL)
        self.store = store
        importer = CodexImporter(
            rootURL: codexRootURL,
            store: store,
            calendar: calendar
        )
        queryService = DashboardQueryService(store: store)
        self.now = now
        self.calendar = calendar
        self.usageCalendar = usageCalendar
        self.accountRateLimitReader = accountRateLimitReader
        self.beforeImport = beforeImport
        self.beforeQuery = beforeQuery
    }

    func loadCached() async throws -> DashboardDataResult {
        try await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        return try await makeResult(importResult: nil)
    }

    func refreshUsage() async throws -> DashboardDataResult {
        try await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await beforeImport(.foreground)
        try Task.checkCancellation()
        let importResult = await importer.refresh(scope: .foreground)
        try Task.checkCancellation()
        try store.persistSourceStatus(
            indexHealth: importResult.indexHealth,
            discoveredFileIDs: importResult.discoveredFileIDs,
            issues: importResult.issues,
            processedFileCount: importResult.processedFileCount
        )
        return try await makeResult(importResult: importResult)
    }

    func refreshQuota() async throws -> DashboardDataResult {
        try await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        return try await makeResult(
            importResult: nil,
            accountRateLimits: await readAccountRateLimits()
        )
    }

    func backfillHistory() async throws -> DashboardDataResult {
        try await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await beforeImport(.history)
        try Task.checkCancellation()
        let importResult = await importer.refresh(scope: .history)
        try Task.checkCancellation()
        try store.persistSourceStatus(
            indexHealth: importResult.indexHealth,
            discoveredFileIDs: importResult.discoveredFileIDs,
            issues: importResult.issues,
            processedFileCount: importResult.processedFileCount
        )
        return try await makeResult(importResult: importResult)
    }

    func rebuildFromLocalData() async throws -> DashboardDataResult {
        try await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        await beforeImport(.history)
        try Task.checkCancellation()
        let importResult = await importer.rebuildFromLocalData()
        try Task.checkCancellation()
        try store.persistSourceStatus(
            indexHealth: importResult.indexHealth,
            discoveredFileIDs: importResult.discoveredFileIDs,
            issues: importResult.issues,
            processedFileCount: importResult.processedFileCount
        )
        return try await makeResult(importResult: importResult)
    }

    private func acquireOperation() async throws {
        try Task.checkCancellation()
        guard operationIsRunning else {
            operationIsRunning = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                operationWaiters.append(OperationWaiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelOperationWaiter(id: id) }
        }
    }

    private func releaseOperation() {
        guard !operationWaiters.isEmpty else {
            operationIsRunning = false
            return
        }
        operationWaiters.removeFirst().continuation.resume()
    }

    private func cancelOperationWaiter(id: UUID) {
        guard let index = operationWaiters.firstIndex(where: { $0.id == id }) else { return }
        operationWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func readAccountRateLimits() async -> CodexAccountRateLimits? {
        guard let accountRateLimitReader else { return nil }
        do {
            let rateLimits = try await accountRateLimitReader.read()
            let windows = rateLimits.windows.map {
                "\($0.windowMinutes)m used=\($0.usedPercent) reset=\($0.resetsAtSeconds ?? -1)"
            }.joined(separator: ", ")
            quotaLogger.debug("Read official account quota: \(windows, privacy: .public)")
            do {
                try store.persistAccountRateLimits(rateLimits)
            } catch {
                quotaLogger.error(
                    "Official account quota cache write failed: \(String(describing: error), privacy: .public)"
                )
            }
            return rateLimits
        } catch {
            quotaLogger.error("Official account quota read failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func makeResult(
        importResult: ImportResult?,
        accountRateLimits: CodexAccountRateLimits? = nil
    ) async throws -> DashboardDataResult {
        await beforeQuery()
        try Task.checkCancellation()
        let currentDate = now()
        let storedSnapshot = try queryService.snapshot(
            now: currentDate,
            calendar: calendar,
            usageCalendar: usageCalendar
        )
        let cachedAccountRateLimits: CodexAccountRateLimits?
        do {
            cachedAccountRateLimits = try store.accountRateLimits()
        } catch {
            quotaLogger.error(
                "Official account quota cache read failed: \(String(describing: error), privacy: .public)"
            )
            cachedAccountRateLimits = nil
        }
        let snapshot = (accountRateLimits ?? cachedAccountRateLimits)?.applying(
            to: storedSnapshot,
            now: currentDate,
            calendar: calendar
        ) ?? storedSnapshot
        let facts = try store.sourceFacts()
        let summary = SourceSummary(
            cli: facts.hasCLIData ? .connected : .missing,
            desktop: facts.hasDesktopData ? .connected : .missing,
            index: sourceHealth(for: facts.indexHealth),
            lastSuccessfulRefresh: facts.lastSuccessfulRefreshMilliseconds.map {
                Date(timeIntervalSince1970: TimeInterval($0) / 1_000)
            }
        )
        let issues = importResult?.issues ?? []
        let hasUsage = snapshot.totalTokens > 0
        let hasDegradedIndex: Bool
        if case .degraded = facts.indexHealth {
            hasDegradedIndex = true
        } else {
            hasDegradedIndex = false
        }

        if hasUsage {
            if !issues.isEmpty || hasDegradedIndex
                || facts.hasDegradedFiles || facts.hasUnsupportedFiles {
                return .stale(
                    snapshot,
                    summary,
                    "部分数据暂不可用，正在显示已成功读取的数据。"
                )
            }
            return .loaded(snapshot, summary)
        }

        if issues.contains(where: { $0.kind == .unsupportedFormat })
            || facts.hasUnsupportedFiles {
            return .unsupported("Codex 数据格式暂不兼容。")
        }
        if facts.hasDegradedFiles {
            throw LiveDashboardDataError.importFailed
        }
        if issues.contains(where: { issue in
            switch issue.kind {
            case .discovery, .read, .decode, .store: true
            case .index, .unsupportedFormat: false
            }
        }) {
            throw LiveDashboardDataError.importFailed
        }
        return .empty(summary)
    }

    private func sourceHealth(for health: CodexIndexHealth) -> SourceHealth {
        switch health {
        case .available: .connected
        case .missing: .missing
        case .degraded: .degraded
        }
    }
}

private struct OperationWaiter {
    let id: UUID
    let continuation: CheckedContinuation<Void, any Error>
}

private enum LiveDashboardDataError: Error {
    case initializationFailed
    case importFailed
}

private actor UnavailableDashboardDataClient: DashboardDataClient {
    func loadCached() async throws -> DashboardDataResult {
        throw LiveDashboardDataError.initializationFailed
    }

    func refreshUsage() async throws -> DashboardDataResult {
        throw LiveDashboardDataError.initializationFailed
    }

    func refreshQuota() async throws -> DashboardDataResult {
        throw LiveDashboardDataError.initializationFailed
    }

    func backfillHistory() async throws -> DashboardDataResult {
        throw LiveDashboardDataError.initializationFailed
    }

    func rebuildFromLocalData() async throws -> DashboardDataResult {
        throw LiveDashboardDataError.initializationFailed
    }
}

@MainActor
@Observable
final class DashboardStore {
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private(set) var state: DashboardLoadState = .loading
    private(set) var isRefreshing = false
    private(set) var isRebuildingData = false
    private(set) var isAutomaticRefreshEnabled: Bool
    private(set) var sourceSummary: SourceSummary?

    private let client: any DashboardDataClient
    private let usageRefreshInterval: Duration
    private let quotaCheckInterval: Duration
    private let sleeper: Sleeper
    private var hasLoadedCached = false
    private var hasStarted = false
    private var publicationRevision: UInt64 = 0
    private var foregroundRevision: UInt64 = 0
    private var startTask: Task<Void, Never>?
    private var inFlightManualRefresh: Task<Void, Never>?
    private var inFlightRefresh: Task<Void, Never>?
    private var inFlightQuotaRefresh: Task<Void, Never>?
    private var inFlightRebuild: Task<Void, Never>?
    private var backfillTask: Task<Void, Never>?
    private var automaticUsageRefreshTask: Task<Void, Never>?
    private var automaticQuotaCheckTask: Task<Void, Never>?
    private var quotaRefreshNeeded = true

    init(
        client: any DashboardDataClient,
        usageRefreshInterval: Duration = .seconds(60),
        quotaCheckInterval: Duration = .seconds(120),
        automaticRefreshEnabled: Bool = true,
        sleeper: @escaping Sleeper = { duration in
            try await ContinuousClock().sleep(for: duration)
        }
    ) {
        self.client = client
        self.usageRefreshInterval = usageRefreshInterval
        self.quotaCheckInterval = quotaCheckInterval
        isAutomaticRefreshEnabled = automaticRefreshEnabled
        self.sleeper = sleeper
    }

    static func live() -> DashboardStore {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
        let databaseURL = home
            .appendingPathComponent("Library/Application Support/SpendScope", isDirectory: true)
            .appendingPathComponent("SpendScope.sqlite")
        let client: any DashboardDataClient
        do {
            client = try LiveDashboardDataClient(
                codexRootURL: codexRoot,
                databaseURL: databaseURL,
                accountRateLimitReader: CodexAppServerRateLimitReader.discover()
            )
        } catch {
            client = UnavailableDashboardDataClient()
        }
        let automaticRefreshEnabled = UserDefaults.standard.object(
            forKey: AppPreferenceKeys.automaticRefreshEnabled
        ) as? Bool ?? true
        let store = DashboardStore(
            client: client,
            automaticRefreshEnabled: automaticRefreshEnabled
        )
        Task { @MainActor [weak store] in
            await store?.start()
        }
        return store
    }

    var snapshot: DashboardSnapshot? {
        switch state {
        case .loaded(let snapshot, _), .stale(let snapshot, _, _): snapshot
        case .loading, .empty, .failed, .unsupported: nil
        }
    }

    func menuBarLabel(configuration: MenuBarLabelConfiguration) -> String {
        snapshot?.menuBarLabel(configuration: configuration) ?? "SpendScope"
    }

    func start() async {
        if let startTask {
            await startTask.value
            return
        }
        guard !hasStarted else { return }
        hasStarted = true

        let task = Task { @MainActor [weak self] in
            await self?.loadCached()
            await self?.refreshUsage()
            self?.launchBackfill()
            self?.launchAutomaticRefresh()
        }
        startTask = task
        await task.value
        startTask = nil
    }

    func loadCached() async {
        guard !hasLoadedCached else { return }
        hasLoadedCached = true
        do {
            publish(try await client.loadCached())
        } catch {
            state = .failed("无法读取已保存的 SpendScope 数据。")
        }
    }

    func refresh() async {
        if let inFlightManualRefresh {
            await inFlightManualRefresh.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshUsage()
            await self.refreshQuota(force: true)
        }
        inFlightManualRefresh = task
        await task.value
        inFlightManualRefresh = nil
    }

    func refreshUsage() async {
        if let inFlightRebuild {
            await inFlightRebuild.value
            return
        }
        if let inFlightRefresh {
            await inFlightRefresh.value
            return
        }

        foregroundRevision &+= 1
        isRefreshing = true
        let previousUsage = usageFingerprint
        let client = self.client
        let task = Task { @MainActor [weak self, client] in
            do {
                let result = try await client.refreshUsage()
                guard !Task.isCancelled else { return }
                self?.publishUsageResult(result, previousUsage: previousUsage)
            } catch {
                guard !Task.isCancelled else { return }
                self?.publishRefreshFailure()
            }
        }
        inFlightRefresh = task
        await task.value
        inFlightRefresh = nil
        isRefreshing = false
    }

    func refreshQuotaIfNeeded() async {
        await refreshQuota(force: false)
    }

    private func refreshQuota(force: Bool) async {
        if let inFlightQuotaRefresh {
            await inFlightQuotaRefresh.value
            return
        }
        guard force || quotaRefreshNeeded else { return }

        quotaRefreshNeeded = false
        let client = self.client
        let task = Task { @MainActor [weak self, client] in
            do {
                let result = try await client.refreshQuota()
                guard !Task.isCancelled else { return }
                self?.publish(result)
            } catch {
                guard !Task.isCancelled else { return }
                self?.quotaRefreshNeeded = true
            }
        }
        inFlightQuotaRefresh = task
        await task.value
        inFlightQuotaRefresh = nil
    }

    func rebuildFromLocalData() async {
        if let inFlightRebuild {
            await inFlightRebuild.value
            return
        }
        if let inFlightRefresh {
            await inFlightRefresh.value
            if let inFlightRebuild {
                await inFlightRebuild.value
                return
            }
        }

        backfillTask?.cancel()
        backfillTask = nil
        foregroundRevision &+= 1
        publicationRevision &+= 1
        let previousUsage = usageFingerprint
        isRebuildingData = true
        sourceSummary = nil
        state = .loading

        let client = self.client
        let task = Task { @MainActor [weak self, client] in
            do {
                let result = try await client.rebuildFromLocalData()
                guard !Task.isCancelled else { return }
                self?.publishUsageResult(result, previousUsage: previousUsage)
            } catch {
                guard !Task.isCancelled else { return }
                self?.publicationRevision &+= 1
                self?.state = .failed("无法重新抓取 Codex 本地数据，请稍后重试。")
            }
        }
        inFlightRebuild = task
        await task.value
        inFlightRebuild = nil
        isRebuildingData = false
    }

    func setAutomaticRefreshEnabled(_ isEnabled: Bool) {
        guard isAutomaticRefreshEnabled != isEnabled else { return }
        isAutomaticRefreshEnabled = isEnabled

        if isEnabled {
            guard hasStarted else { return }
            launchAutomaticRefresh()
        } else {
            automaticUsageRefreshTask?.cancel()
            automaticUsageRefreshTask = nil
            automaticQuotaCheckTask?.cancel()
            automaticQuotaCheckTask = nil
        }
    }

    private func launchBackfill() {
        guard backfillTask == nil else { return }
        let client = self.client
        let capturedPublicationRevision = publicationRevision
        let capturedForegroundRevision = foregroundRevision
        let previousUsage = usageFingerprint
        backfillTask = Task { @MainActor [weak self, client] in
            do {
                let result = try await client.backfillHistory()
                guard !Task.isCancelled,
                      let self,
                      self.publicationRevision == capturedPublicationRevision,
                      self.foregroundRevision == capturedForegroundRevision else {
                    return
                }
                self.publishUsageResult(result, previousUsage: previousUsage)
            } catch {
                // Foreground state remains authoritative when optional history work fails.
            }
        }
    }

    private func launchAutomaticRefresh() {
        guard isAutomaticRefreshEnabled else { return }
        let sleeper = self.sleeper
        if automaticUsageRefreshTask == nil {
            let interval = usageRefreshInterval
            automaticUsageRefreshTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do {
                        try await sleeper(interval)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    await self?.refreshUsage()
                }
            }
        }
        if automaticQuotaCheckTask == nil {
            let interval = quotaCheckInterval
            automaticQuotaCheckTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do {
                        try await sleeper(interval)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    await self?.refreshQuotaIfNeeded()
                }
            }
        }
    }

    private var usageFingerprint: UsageFingerprint? {
        snapshot.flatMap(UsageFingerprint.init)
    }

    private func publishUsageResult(
        _ result: DashboardDataResult,
        previousUsage: UsageFingerprint?
    ) {
        publish(result)
        if previousUsage != usageFingerprint {
            quotaRefreshNeeded = true
        }
    }

    private func publish(_ result: DashboardDataResult) {
        publicationRevision &+= 1
        switch result {
        case .loaded(let snapshot, let summary):
            sourceSummary = summary
            state = .loaded(snapshot, summary)
        case .empty(let summary):
            sourceSummary = summary
            state = .empty(summary)
        case .stale(let snapshot, let summary, let message):
            sourceSummary = summary
            state = .stale(snapshot, summary, message)
        case .unsupported(let message):
            if let snapshot, let summary = sourceSummary {
                state = .stale(snapshot, summary, "数据格式发生变化，正在显示上次可用数据。")
            } else {
                state = .unsupported(message)
            }
        }
    }

    private func publishRefreshFailure() {
        publicationRevision &+= 1
        if let snapshot, let summary = sourceSummary {
            state = .stale(snapshot, summary, "暂时无法刷新，正在显示上次可用数据。")
        } else {
            state = .failed("暂时无法读取 Codex 数据，请稍后重试。")
        }
    }

    isolated deinit {
        startTask?.cancel()
        inFlightManualRefresh?.cancel()
        inFlightRefresh?.cancel()
        inFlightQuotaRefresh?.cancel()
        inFlightRebuild?.cancel()
        backfillTask?.cancel()
        automaticUsageRefreshTask?.cancel()
        automaticQuotaCheckTask?.cancel()
    }
}

private struct UsageFingerprint: Equatable {
    let uncachedInput: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int

    init?(_ snapshot: DashboardSnapshot) {
        guard let allTime = snapshot.periods.first(where: { $0.id == "allTime" }) else {
            return nil
        }
        uncachedInput = allTime.uncachedInput
        cachedInput = allTime.cachedInput
        output = allTime.output
        reasoning = allTime.reasoning
    }
}
