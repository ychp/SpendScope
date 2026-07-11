import XCTest
@testable import SpendScope

final class TokenFormatterTests: XCTestCase {
    func testFormatsCompactValues() {
        XCTAssertEqual(TokenFormatter.compact(999), "999")
        XCTAssertEqual(TokenFormatter.compact(1_500), "1.5K")
        XCTAssertEqual(TokenFormatter.compact(17_000_000), "17.0M")
        XCTAssertEqual(TokenFormatter.compact(1_061_100_000), "1.1B")
    }

    func testFormatsPercentagesWithOneDecimalPlace() {
        XCTAssertEqual(TokenFormatter.percentage(0.48235), "48.2%")
        XCTAssertEqual(TokenFormatter.percentage(0), "0.0%")
        XCTAssertEqual(TokenFormatter.percentage(1), "100.0%")
    }
}

final class DashboardSnapshotTests: XCTestCase {
    func testPeriodShareUsesCurrentPeriodTotal() {
        let today = DashboardSnapshot.preview.periods[0]

        XCTAssertEqual(today.share(of: today.uncachedInput), 0.48235, accuracy: 0.00001)
    }

    func testPeriodShareHandlesZeroAndClampsInvalidValues() {
        let zeroTotal = PeriodUsage(
            id: "zero",
            title: "空周期",
            total: 0,
            uncachedInput: 0,
            cachedInput: 0,
            output: 0,
            reasoning: 0
        )
        let regular = DashboardSnapshot.preview.periods[0]

        XCTAssertEqual(zeroTotal.share(of: 10), 0)
        XCTAssertEqual(regular.share(of: -1), 0)
        XCTAssertEqual(regular.share(of: regular.total + 1), 1)
    }

    func testQuotaCenterLabelsUseCompactPeriods() {
        let quotas = DashboardSnapshot.preview.quotas

        XCTAssertEqual(quotas.map(\.compactTitle), ["5H", "7d"])
        XCTAssertEqual(quotas.map(\.remainingLabel), ["5H 85%", "7d 84%"])
    }

    func testPreviewQuotaResetTextUsesDashboardFormat() {
        let quotas = DashboardSnapshot.preview.quotas

        XCTAssertEqual(quotas.map(\.resetText), ["02:52", "2026-07-13 10:45"])
        XCTAssertFalse(quotas.contains { $0.resetText.contains("重置") })
    }

    func testPreviewPeriodsUseConsistentTotals() {
        let periods = DashboardSnapshot.preview.periods

        XCTAssertEqual(periods.map(\.title), ["今日", "7 日", "30 日", "累计"])
        XCTAssertEqual(periods.count, 4)

        for period in periods {
            XCTAssertEqual(
                period.total,
                period.uncachedInput
                    + period.cachedInput
                    + period.visibleOutput
                    + period.reasoning
            )
        }
    }

    func testTodayBreakdownSplitsReasoningFromOutput() {
        let snapshot = DashboardSnapshot.preview
        let today = snapshot.periods[0]

        XCTAssertEqual(snapshot.todayTokens, today.total)
        XCTAssertEqual(snapshot.thirtyDayTokens, snapshot.periods[2].total)
        XCTAssertEqual(snapshot.totalTokens, snapshot.periods[3].total)
        XCTAssertEqual(snapshot.breakdown.input, today.uncachedInput)
        XCTAssertEqual(snapshot.breakdown.cachedInput, today.cachedInput)
        XCTAssertEqual(snapshot.breakdown.output, today.visibleOutput)
        XCTAssertEqual(snapshot.breakdown.reasoning, today.reasoning)
        XCTAssertEqual(snapshot.breakdown.total, today.total)
    }
}
