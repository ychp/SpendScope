import Foundation
import XCTest
@testable import SpendScope

final class UsageReminderEvaluatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testConfigurationDefaultsToDisabledWithEveryQuotaAndThresholdSelected() {
        let defaults = makeDefaults()
        let configuration = UsageReminderConfiguration.load(from: defaults)

        XCTAssertFalse(configuration.isEnabled)
        XCTAssertEqual(configuration.quotas, Set(UsageReminderQuota.allCases))
        XCTAssertEqual(configuration.thresholds, Set(UsageReminderThreshold.allCases))
    }

    func testFirstObservationUsesMostUrgentReachedThresholdAndMarksHigherLevels() throws {
        let evaluation = evaluate(remaining: 0.10)

        XCTAssertEqual(evaluation.events.map(\.threshold), [.ten])
        let state = try XCTUnwrap(evaluation.deliveredCheckpoint.quotas["5h"])
        XCTAssertEqual(state.deliveredThresholds, [20, 10])

        let aboveBoundary = evaluate(remaining: 0.200_001)
        XCTAssertTrue(aboveBoundary.events.isEmpty)
        XCTAssertEqual(evaluate(remaining: 0.20).events.map(\.threshold), [.twenty])
    }

    func testProgressiveThresholdsFireOncePerCycle() throws {
        let first = evaluate(remaining: 0.19)
        XCTAssertEqual(first.events.map(\.threshold), [.twenty])

        let second = evaluate(
            remaining: 0.09,
            observedOffset: 60,
            checkpoint: first.deliveredCheckpoint
        )
        XCTAssertEqual(second.events.map(\.threshold), [.ten])

        let repeated = evaluate(
            remaining: 0.09,
            observedOffset: 120,
            checkpoint: second.deliveredCheckpoint
        )
        XCTAssertTrue(repeated.events.isEmpty)

        let third = evaluate(
            remaining: 0.04,
            observedOffset: 180,
            checkpoint: repeated.deliveredCheckpoint
        )
        XCTAssertEqual(third.events.map(\.threshold), [.five])
        XCTAssertEqual(
            try XCTUnwrap(third.deliveredCheckpoint.quotas["5h"]).deliveredThresholds,
            [20, 10, 5]
        )
    }

    func testJumpingAcrossAllLevelsSendsOnlyFivePercentReminder() throws {
        let evaluation = evaluate(remaining: 0.04)

        XCTAssertEqual(evaluation.events.map(\.threshold), [.five])
        XCTAssertEqual(
            try XCTUnwrap(evaluation.deliveredCheckpoint.quotas["5h"]).deliveredThresholds,
            [20, 10, 5]
        )
    }

    func testNewResetCycleRearmsButOlderObservationIsIgnored() {
        let first = evaluate(remaining: 0.19)
        let sameCycleRecovery = evaluate(
            remaining: 0.80,
            observedOffset: 60,
            checkpoint: first.deliveredCheckpoint
        )
        XCTAssertTrue(sameCycleRecovery.events.isEmpty)

        let newCycle = evaluate(
            remaining: 0.19,
            observedOffset: 120,
            resetOffset: 14_400,
            checkpoint: sameCycleRecovery.deliveredCheckpoint
        )
        XCTAssertEqual(newCycle.events.map(\.threshold), [.twenty])

        let older = evaluate(
            remaining: 0.04,
            observedOffset: 30,
            resetOffset: 18_000,
            checkpoint: newCycle.deliveredCheckpoint
        )
        XCTAssertTrue(older.events.isEmpty)
        XCTAssertEqual(older.baselineCheckpoint, newCycle.deliveredCheckpoint)
    }

    func testScopeSelectionAndCombinedNotificationAreDeterministic() throws {
        let configuration = UsageReminderConfiguration(
            isEnabled: true,
            quotas: [.fiveHour, .weekly],
            thresholds: [.twenty, .ten, .five]
        )
        let evaluation = UsageReminderEvaluator.evaluate(
            quotas: [
                quota(.weekly, remaining: 0.09),
                quota(.fiveHour, remaining: 0.19)
            ],
            configuration: configuration,
            checkpoint: .empty,
            now: now
        )
        let notification = try XCTUnwrap(UsageReminderNotification(events: evaluation.events))

        XCTAssertEqual(evaluation.events.map(\.quota), [.fiveHour, .weekly])
        XCTAssertEqual(notification.title, "Codex 额度提醒")
        XCTAssertEqual(
            notification.body,
            "5H 剩余 19%，1 小时后重置。\n7d 剩余 9%，1 小时后重置。"
        )
        XCTAssertTrue(notification.identifier.hasPrefix(UsageReminderNotification.identifierPrefix))
    }

    func testCheckpointCodecIsVersionedAndContainsNoConversationData() throws {
        let checkpoint = evaluate(remaining: 0.19).deliveredCheckpoint
        let data = try XCTUnwrap(UsageReminderCheckpointCodec.encode(checkpoint))
        let encoded = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(UsageReminderCheckpointCodec.decode(data), checkpoint)
        XCTAssertFalse(encoded.contains("private prompt text"))
        XCTAssertFalse(encoded.contains("sourceFile"))
        XCTAssertEqual(
            UsageReminderCheckpointCodec.decode(Data("{}".utf8)),
            .empty
        )
    }

    private func evaluate(
        remaining: Double,
        observedOffset: TimeInterval = 0,
        resetOffset: TimeInterval = 3_600,
        checkpoint: UsageReminderCheckpoint = .empty
    ) -> UsageReminderEvaluation {
        UsageReminderEvaluator.evaluate(
            quotas: [quota(
                .fiveHour,
                remaining: remaining,
                observedOffset: observedOffset,
                resetOffset: resetOffset
            )],
            configuration: UsageReminderConfiguration(
                isEnabled: true,
                quotas: [.fiveHour],
                thresholds: [.twenty, .ten, .five]
            ),
            checkpoint: checkpoint,
            now: now
        )
    }

    private func quota(
        _ kind: UsageReminderQuota,
        remaining: Double,
        observedOffset: TimeInterval = 0,
        resetOffset: TimeInterval = 3_600
    ) -> QuotaSnapshot {
        QuotaSnapshot(
            id: kind.rawValue,
            title: kind.title,
            remaining: remaining,
            resetText: "",
            resetsAt: now.addingTimeInterval(resetOffset),
            observedAt: now.addingTimeInterval(observedOffset)
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageReminderEvaluatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
final class UsageReminderControllerTests: XCTestCase {
    func testDeniedPermissionKeepsThresholdPendingAndAuthorizationLaterDelivers() async {
        let now = Date()
        let snapshot = reminderSnapshot(now: now, remaining: 0.09)
        let store = DashboardStore(
            client: ReminderDashboardClient(result: .loaded(snapshot, .reminderFixture))
        )
        await store.loadCached()
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppPreferenceKeys.usageRemindersEnabled)
        let client = FakeUsageNotificationClient(status: .denied)
        let controller = UsageReminderController(
            store: store,
            defaults: defaults,
            notificationClient: client
        )

        controller.start()
        await eventually {
            controller.authorizationStatus == .denied
                && UsageReminderCheckpointCodec.decode(
                    defaults.data(forKey: AppPreferenceKeys.usageReminderCheckpoint)
                ).quotas["5h"] != nil
        }
        XCTAssertTrue(client.deliveries.isEmpty)
        XCTAssertEqual(controller.authorizationStatus, .denied)
        let deniedCheckpoint = UsageReminderCheckpointCodec.decode(
            defaults.data(forKey: AppPreferenceKeys.usageReminderCheckpoint)
        )
        XCTAssertTrue(deniedCheckpoint.quotas["5h"]?.deliveredThresholds.isEmpty == true)

        client.status = .authorized
        controller.applicationDidBecomeActive()
        await eventually { client.deliveries.count == 1 }
        XCTAssertEqual(client.deliveries.first?.title, "Codex 额度提醒")
        let deliveredCheckpoint = UsageReminderCheckpointCodec.decode(
            defaults.data(forKey: AppPreferenceKeys.usageReminderCheckpoint)
        )
        XCTAssertEqual(deliveredCheckpoint.quotas["5h"]?.deliveredThresholds, [20, 10])
    }

    func testDeliveryFailureDoesNotConsumeThreshold() async {
        let now = Date()
        let snapshot = reminderSnapshot(now: now, remaining: 0.19)
        let store = DashboardStore(
            client: ReminderDashboardClient(result: .loaded(snapshot, .reminderFixture))
        )
        await store.loadCached()
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppPreferenceKeys.usageRemindersEnabled)
        let client = FakeUsageNotificationClient(status: .authorized, shouldFail: true)
        let controller = UsageReminderController(
            store: store,
            defaults: defaults,
            notificationClient: client
        )

        controller.start()
        await eventually { client.deliveryAttempts == 1 }
        let checkpoint = UsageReminderCheckpointCodec.decode(
            defaults.data(forKey: AppPreferenceKeys.usageReminderCheckpoint)
        )
        XCTAssertTrue(checkpoint.quotas["5h"]?.deliveredThresholds.isEmpty == true)
    }

    private func reminderSnapshot(now: Date, remaining: Double) -> DashboardSnapshot {
        DashboardSnapshot(
            planName: "Plus",
            updatedText: "刚刚",
            periods: [
                PeriodUsage(
                    id: "allTime", title: "累计", total: 1,
                    uncachedInput: 1, cachedInput: 0, output: 0, reasoning: 0
                )
            ],
            quotas: [
                QuotaSnapshot(
                    id: "5h", title: "5 小时", remaining: remaining, resetText: "",
                    resetsAt: now.addingTimeInterval(3_600), observedAt: now
                )
            ],
            models: [],
            dailyUsage: []
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "UsageReminderControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func eventually(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not met before timeout")
    }
}

@MainActor
private final class FakeUsageNotificationClient: UsageNotificationClient {
    var status: UsageReminderAuthorizationStatus
    var shouldFail: Bool
    private(set) var deliveries: [UsageReminderNotification] = []
    private(set) var deliveryAttempts = 0

    init(status: UsageReminderAuthorizationStatus, shouldFail: Bool = false) {
        self.status = status
        self.shouldFail = shouldFail
    }

    func authorizationStatus() async -> UsageReminderAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        status = .authorized
        return true
    }

    func deliver(_ notification: UsageReminderNotification) async throws {
        deliveryAttempts += 1
        if shouldFail { throw ReminderTestError.deliveryFailed }
        deliveries.append(notification)
    }
}

private actor ReminderDashboardClient: DashboardDataClient {
    let result: DashboardDataResult

    init(result: DashboardDataResult) {
        self.result = result
    }

    func loadCached() async throws -> DashboardDataResult { result }
    func refreshUsage() async throws -> DashboardDataResult { result }
    func refreshQuota() async throws -> DashboardDataResult { result }
    func backfillHistory() async throws -> DashboardDataResult { result }
    func rebuildFromLocalData() async throws -> DashboardDataResult { result }
}

private enum ReminderTestError: Error {
    case deliveryFailed
}

private extension SourceSummary {
    static let reminderFixture = SourceSummary(
        cli: .connected,
        desktop: .connected,
        index: .connected,
        lastSuccessfulRefresh: Date()
    )
}
