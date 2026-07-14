import Foundation
import XCTest
@testable import SpendScope

final class DashboardQueryServiceTests: XCTestCase {
    func testBuildsLocalDayPeriodsTrendModelsQuotasAndDeterministicPlan() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 14, hour: 12
        )))
        let todayStart = calendar.startOfDay(for: now)
        let sevenDayStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: todayStart))
        let thirtyDayStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -29, to: todayStart))
        let store = try makeStore()

        let events = [
            usage("today", at: todayStart.addingTimeInterval(60), total: 160,
                  usage: .init(uncachedInput: 100, cachedInput: 20, visibleOutput: 30, reasoning: 10)),
            usage("before-today", at: todayStart.addingTimeInterval(-1), total: 200),
            usage("seven-start", at: sevenDayStart, total: 300),
            usage("before-seven", at: sevenDayStart.addingTimeInterval(-1), total: 400),
            usage("thirty-start", at: thirtyDayStart, total: 500),
            usage("before-thirty", at: thirtyDayStart.addingTimeInterval(-1), total: 600),
            usage("latest-a", at: now.addingTimeInterval(-1), total: 1, model: "model-a", planRaw: "free"),
            usage("latest-z", at: now.addingTimeInterval(-1), total: 1, model: "model-z", planRaw: "plus")
        ]
        try store.commit(batch(
            events: events,
            quotas: [
                quota("5h", kind: .fiveHour, now: now, reset: now.addingTimeInterval(2 * 3_600)),
                quota("7d", kind: .weekly, now: now, reset: now.addingTimeInterval(7 * 86_400))
            ]
        ))

        let snapshot = try DashboardQueryService(store: store).snapshot(now: now, calendar: calendar)

        XCTAssertEqual(snapshot.periods.map(\.id), ["today", "sevenDays", "thirtyDays", "allTime"])
        XCTAssertEqual(snapshot.periods.map(\.title), ["今日", "7 日", "30 日", "累计"])
        XCTAssertEqual(snapshot.periods.map(\.total), [162, 662, 1_562, 2_162])
        XCTAssertEqual(snapshot.breakdown.input, 102)
        XCTAssertEqual(snapshot.breakdown.cachedInput, 20)
        XCTAssertEqual(snapshot.breakdown.output, 30)
        XCTAssertEqual(snapshot.breakdown.reasoning, 10)
        XCTAssertEqual(snapshot.periods.first?.output, 40, "PeriodUsage.output remains raw output")
        XCTAssertEqual(snapshot.visibleQuotas.map(\.id), ["5h", "7d"])
        XCTAssertEqual(snapshot.visibleQuotas.map(\.resetText), ["14:00", "2026-07-21 12:00"])
        XCTAssertEqual(snapshot.planName, "Plus")
        XCTAssertTrue(snapshot.issues.isEmpty)
        XCTAssertEqual(snapshot.dailyUsage.count, 31)
        XCTAssertEqual(snapshot.dailyUsage.map(\.id), snapshot.dailyUsage.map(\.id).sorted())
        XCTAssertTrue(snapshot.dailyUsage.contains { $0.total == 0 })
        XCTAssertEqual(snapshot.models.first?.name, "test-model")
        XCTAssertEqual(snapshot.models.reduce(0) { $0 + $1.share }, 1, accuracy: 0.000_001)
        XCTAssertTrue(snapshot.models.allSatisfy { $0.share.isFinite && $0.share >= 0 })
    }

    func testOmitsExpiredAndInvalidQuotaObservationsWithSafeIssues() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.commit(batch(
            events: [],
            quotas: [
                quota("expired", kind: .fiveHour, now: now, reset: now.addingTimeInterval(-1)),
                quota("missing-reset", kind: .weekly, now: now, reset: nil)
            ]
        ))

        let snapshot = try DashboardQueryService(store: store).snapshot(now: now, calendar: calendar)

        XCTAssertTrue(snapshot.visibleQuotas.isEmpty)
        XCTAssertEqual(Set(snapshot.issues), [.expiredQuota(id: "5h"), .invalidQuota(id: "7d")])
    }

    func testReturnsFourZeroPeriodsWhenStoreHasNoUsage() throws {
        let snapshot = try DashboardQueryService(store: makeStore()).snapshot(
            now: Date(timeIntervalSince1970: 1_000),
            calendar: .current
        )

        XCTAssertEqual(snapshot.periods.count, 4)
        XCTAssertTrue(snapshot.periods.allSatisfy { $0.total == 0 })
        XCTAssertTrue(snapshot.quotas.isEmpty)
        XCTAssertTrue(snapshot.models.isEmpty)
        XCTAssertTrue(snapshot.dailyUsage.isEmpty)
        XCTAssertEqual(snapshot.planName, "Free")
    }

    func testAggregateOverflowThrowsInsteadOfWrapping() throws {
        let store = try makeStore()
        try store.commit(batch(
            events: [
                usage("max", at: Date(timeIntervalSince1970: 0), total: Int64.max),
                usage("one", at: Date(timeIntervalSince1970: 3_600), total: 1)
            ],
            quotas: []
        ))

        XCTAssertThrowsError(try DashboardQueryService(store: store).snapshot(
            now: Date(timeIntervalSince1970: 7_200), calendar: .current
        )) { error in
            guard case DashboardQueryError.tokenOverflow = error else {
                return XCTFail("Expected controlled token overflow, got \(error)")
            }
        }
    }

    func testEmptyAndMalformedSnapshotsUseStableIDLookupWithoutCrashing() {
        let empty = DashboardSnapshot.empty(updatedText: "未刷新")
        XCTAssertEqual(empty.periods.map(\.id), ["today", "sevenDays", "thirtyDays", "allTime"])
        XCTAssertEqual(empty.todayTokens, 0)
        XCTAssertEqual(empty.breakdown.total, 0)

        let malformed = DashboardSnapshot(
            planName: "Free",
            updatedText: "未刷新",
            periods: [PeriodUsage(
                id: "allTime", title: "累计", total: 7,
                uncachedInput: 7, cachedInput: 0, output: 0, reasoning: 0
            )],
            quotas: [],
            models: [],
            dailyUsage: []
        )
        XCTAssertEqual(malformed.todayTokens, 0)
        XCTAssertEqual(malformed.sevenDayTokens, 0)
        XCTAssertEqual(malformed.thirtyDayTokens, 0)
        XCTAssertEqual(malformed.totalTokens, 7)
        XCTAssertEqual(malformed.breakdown.total, 0)
    }

    private func makeStore() throws -> UsageStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardQueryServiceTests-\(UUID().uuidString).sqlite3")
        return try UsageStore(databaseURL: url)
    }

    private func usage(
        _ fingerprint: String,
        at date: Date,
        total: Int64,
        usage: TokenUsageDelta? = nil,
        model: String = "test-model",
        planRaw: String = "plus"
    ) -> StoredUsageEvent {
        StoredUsageEvent(
            fingerprint: fingerprint,
            observedAtMilliseconds: Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            threadID: "thread-1",
            sourceKind: .cli,
            model: model,
            plan: PlanResolver.resolve(rawValue: planRaw),
            usage: usage ?? .init(uncachedInput: total, cachedInput: 0, visibleOutput: 0, reasoning: 0),
            sourceFileID: "file-1",
            sourceOffset: 1
        )
    }

    private func quota(
        _ fingerprint: String,
        kind: QuotaKind,
        now: Date,
        reset: Date?
    ) -> StoredQuotaEvent {
        StoredQuotaEvent(
            fingerprint: fingerprint,
            threadID: "thread-1",
            observation: QuotaObservation(
                kind: kind,
                observedAtMilliseconds: Int64((now.timeIntervalSince1970 * 1_000).rounded()),
                windowMinutes: kind == .fiveHour ? 300 : 10_080,
                remaining: 0.75,
                resetsAtMilliseconds: reset.map { Int64(($0.timeIntervalSince1970 * 1_000).rounded()) },
                plan: PlanResolver.resolve(rawValue: "plus")
            ),
            sourceKind: .cli
        )
    }

    private func batch(
        events: [StoredUsageEvent],
        quotas: [StoredQuotaEvent]
    ) -> ImportBatch {
        ImportBatch(
            file: FileCheckpoint(
                fileID: "file-1", deviceID: 1, inode: 1,
                path: "/synthetic/dashboard.jsonl", fileSize: 10, committedOffset: 10,
                generation: 0, threadID: "thread-1", lastRecordAtMilliseconds: nil,
                lastSuccessAtMilliseconds: nil, formatStatus: "supported", lastError: nil
            ),
            usageEvents: events,
            quotaEvents: quotas,
            stateEvents: [],
            sessions: [],
            threadCheckpoints: []
        )
    }
}
