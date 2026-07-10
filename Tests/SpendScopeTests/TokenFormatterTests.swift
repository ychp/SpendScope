import XCTest
@testable import SpendScope

final class TokenFormatterTests: XCTestCase {
    func testFormatsCompactValues() {
        XCTAssertEqual(TokenFormatter.compact(999), "999")
        XCTAssertEqual(TokenFormatter.compact(1_500), "1.5K")
        XCTAssertEqual(TokenFormatter.compact(17_000_000), "17.0M")
        XCTAssertEqual(TokenFormatter.compact(1_061_100_000), "1.1B")
    }
}

final class DashboardSnapshotTests: XCTestCase {
    func testPreviewPeriodsUseConsistentTotals() {
        XCTAssertEqual(DashboardSnapshot.preview.periods.count, 3)

        for period in DashboardSnapshot.preview.periods {
            XCTAssertEqual(
                period.total,
                period.uncachedInput + period.cachedInput + period.output
            )
        }
    }

    func testTodayBreakdownSplitsReasoningFromOutput() {
        let snapshot = DashboardSnapshot.preview
        let today = snapshot.periods[0]

        XCTAssertEqual(snapshot.todayTokens, today.total)
        XCTAssertEqual(snapshot.breakdown.input, today.uncachedInput)
        XCTAssertEqual(snapshot.breakdown.cachedInput, today.cachedInput)
        XCTAssertEqual(snapshot.breakdown.output, today.output - today.reasoning)
        XCTAssertEqual(snapshot.breakdown.reasoning, today.reasoning)
        XCTAssertEqual(snapshot.breakdown.total, today.total)
    }
}
