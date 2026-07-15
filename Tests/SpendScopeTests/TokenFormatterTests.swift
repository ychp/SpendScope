import AppKit
import Foundation
import XCTest
@testable import SpendScope

private extension DashboardSnapshot {
    static let preview: DashboardSnapshot = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let startDate = calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 28)
        ) ?? Date(timeIntervalSince1970: 0)
        let dailyUsage = (0..<45).compactMap { index -> DailyUsage? in
            guard let date = calendar.date(byAdding: .day, value: index, to: startDate) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year,
                  let month = components.month,
                  let day = components.day else {
                return nil
            }
            let total = 8_400_000 + (index % 10) * 650_000 + (index / 10) * 300_000
            return DailyUsage(
                id: String(format: "%04d-%02d-%02d", year, month, day),
                day: String(format: "%d/%d", month, day),
                total: total
            )
        }
        return DashboardSnapshot(
            planName: "Pro",
            updatedText: "刚刚刷新",
            periods: [
                PeriodUsage(
                    id: "today", title: "今日", total: 17_000_000,
                    uncachedInput: 8_200_000, cachedInput: 7_900_000,
                    output: 900_000, reasoning: 200_000
                ),
                PeriodUsage(
                    id: "sevenDays", title: "7 日", total: 84_200_000,
                    uncachedInput: 35_200_000, cachedInput: 45_500_000,
                    output: 3_500_000, reasoning: 900_000
                ),
                PeriodUsage(
                    id: "thirtyDays", title: "30 日", total: 198_600_000,
                    uncachedInput: 78_400_000, cachedInput: 112_100_000,
                    output: 8_100_000, reasoning: 1_900_000
                ),
                PeriodUsage(
                    id: "allTime", title: "累计", total: 326_800_000,
                    uncachedInput: 128_000_000, cachedInput: 184_000_000,
                    output: 14_800_000, reasoning: 3_400_000
                )
            ],
            quotas: [
                QuotaSnapshot(
                    id: "5h", title: "5 小时", remaining: 0.85, resetText: "02:52"
                ),
                QuotaSnapshot(
                    id: "7d", title: "7 天", remaining: 0.84,
                    resetText: "2026-07-13 10:45"
                )
            ],
            models: [
                ModelUsage(id: "gpt-5.5", name: "gpt-5.5", share: 0.68),
                ModelUsage(id: "gpt-5.4", name: "gpt-5.4", share: 0.32)
            ],
            dailyUsage: dailyUsage
        )
    }()
}

final class TokenFormatterTests: XCTestCase {
    func testMenuQuotaResetTextUsesRelativeDescriptionAndLabeledFallback() {
        let now = Date(timeIntervalSince1970: 1_000)
        let relativeQuota = QuotaSnapshot(
            id: "7d",
            title: "7 天",
            remaining: 0.52,
            resetText: "2026-07-22 10:08",
            resetsAt: now.addingTimeInterval(6 * 86_400)
        )
        let fallbackQuota = QuotaSnapshot(
            id: "7d",
            title: "7 天",
            remaining: 0.52,
            resetText: "2026-07-22 10:08"
        )

        XCTAssertEqual(MenuBarQuotaResetText.text(for: relativeQuota, now: now), "6 天后重置")
        XCTAssertEqual(
            MenuBarQuotaResetText.text(for: fallbackQuota, now: now),
            "2026-07-22 10:08 重置"
        )
    }

    func testMenuSummaryLayoutStacksOnlyWhenBothQuotasAreVisible() {
        XCTAssertEqual(MenuBarSummaryLayout.layout(forQuotaCount: 0), .sideBySide)
        XCTAssertEqual(MenuBarSummaryLayout.layout(forQuotaCount: 1), .sideBySide)
        XCTAssertEqual(MenuBarSummaryLayout.layout(forQuotaCount: 2), .stacked)
    }

    func testQuotaObservationDescriptionUsesActualObservationAge() {
        let now = Date(timeIntervalSince1970: 100_000)
        let quota = QuotaSnapshot(
            id: "7d",
            title: "7 天",
            remaining: 0.52,
            resetText: "2026-07-22 10:08",
            observedAt: now.addingTimeInterval(-125)
        )

        XCTAssertEqual(quota.observationDescription(now: now), "2 分钟前观测")
        XCTAssertEqual(
            MenuBarQuotaTimingText.text(for: quota, now: now),
            "2026-07-22 10:08 重置 · 2 分钟前观测"
        )
    }

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

@MainActor
final class StatusItemPresentationTests: XCTestCase {
    func testUsesCodexUCompatibleCanvasAndIconMetrics() {
        let presentation = StatusItemPresentation(
            snapshot: .preview,
            configuration: .standard,
            displayMode: .rich
        )

        XCTAssertEqual(presentation.imageSize.height, 22)
        XCTAssertEqual(StatusItemLayoutMetrics.iconRect, NSRect(x: 2, y: 2, width: 18, height: 18))
        XCTAssertEqual(StatusItemLayoutMetrics.elementSpacing, 5)
        XCTAssertEqual(
            StatusItemLayoutMetrics.leadingContentWidth,
            StatusItemLayoutMetrics.iconRect.maxX + StatusItemLayoutMetrics.elementSpacing
        )
        XCTAssertEqual(presentation.itemLength, presentation.imageSize.width + 8)

        guard let appearance = NSAppearance(named: .aqua) else {
            return XCTFail("Expected the standard Aqua appearance to be available")
        }
        let image = StatusItemRenderer().render(presentation, appearance: appearance)
        XCTAssertEqual(image.size, presentation.imageSize)
        XCTAssertFalse(image.isTemplate)
    }

    func testBuildsOnlyQuotaMetricsAndClassicUsesCompactWidth() {
        let rich = StatusItemPresentation(
            snapshot: .preview,
            configuration: .standard,
            displayMode: .rich
        )
        let classic = StatusItemPresentation(
            snapshot: .preview,
            configuration: .standard,
            displayMode: .classic
        )

        XCTAssertEqual(rich.metrics.map(\.label), ["5H", "7d"])
        XCTAssertEqual(rich.metrics.map(\.value), ["85%", "84%"])
        XCTAssertEqual(rich.metrics.map(\.paletteRole), [.fiveHour, .weekly])
        XCTAssertFalse(rich.label.contains("今日"))
        XCTAssertLessThan(classic.imageSize.width, rich.imageSize.width)
    }

    func testCountdownPreferenceControlsInlineResetAndCodexStyleTooltip() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = DashboardSnapshot(
            planName: "Pro 20x",
            updatedText: "刚刚",
            periods: DashboardSnapshot.preview.periods,
            quotas: [
                QuotaSnapshot(
                    id: "7d", title: "7 天", remaining: 0.57, resetText: "",
                    resetsAt: now.addingTimeInterval(6 * 86_400)
                )
            ],
            models: [],
            dailyUsage: []
        )
        let visible = StatusItemPresentation(
            snapshot: snapshot,
            configuration: .standard,
            displayMode: .rich,
            now: now
        )
        let hidden = StatusItemPresentation(
            snapshot: snapshot,
            configuration: MenuBarLabelConfiguration(
                quotaDisplay: .remaining,
                showsFiveHour: true,
                showsWeekly: true,
                showsResetCountdown: false
            ),
            displayMode: .rich,
            now: now
        )

        XCTAssertEqual(visible.metrics.first?.resetText, "6d")
        XCTAssertTrue(visible.tooltip.contains("7 天额度 剩余 57%，6 天后重置"))
        XCTAssertTrue(visible.tooltip.contains("点击查看用量"))
        XCTAssertFalse(visible.tooltip.contains("Codex 用量菜单"))
        XCTAssertNil(hidden.metrics.first?.resetText)
        XCTAssertFalse(hidden.tooltip.contains("重置"))
        XCTAssertLessThan(hidden.imageSize.width, visible.imageSize.width)
        XCTAssertEqual(
            visible.imageSize.width,
            StatusItemLayoutMetrics.leadingContentWidth
                + StatusItemLayoutMetrics.richValueWidth
                + StatusItemLayoutMetrics.elementSpacing
                + StatusItemLayoutMetrics.richResetWidth
                + 2
        )
        XCTAssertEqual(
            hidden.imageSize.width,
            StatusItemLayoutMetrics.leadingContentWidth
                + StatusItemLayoutMetrics.richValueWidth
                + 2
        )
    }
}

final class DashboardSnapshotTests: XCTestCase {
    func testTrendRangesExposeExpectedLabelsAndDefault() {
        XCTAssertEqual(TrendRange.allCases.map(\.rawValue), ["今日", "7 天", "30 天", "全部"])
        XCTAssertEqual(TrendRange.defaultRange, .sevenDays)
    }

    func testTrendRangesSelectLatestUsage() {
        let history = makeDailyUsage(count: 45)

        XCTAssertEqual(TrendRange.today.select(from: history).map(\.total), [45])
        XCTAssertEqual(TrendRange.sevenDays.select(from: history).map(\.total), Array(39...45))
        XCTAssertEqual(TrendRange.thirtyDays.select(from: history).map(\.total), Array(16...45))
        XCTAssertEqual(TrendRange.all.select(from: history).map(\.total), Array(1...45))
    }

    func testTrendRangeHandlesLimitedAndEmptyUsage() {
        let limited = makeDailyUsage(count: 3)

        XCTAssertEqual(TrendRange.sevenDays.select(from: limited).map(\.total), [1, 2, 3])
        XCTAssertTrue(TrendRange.thirtyDays.select(from: []).isEmpty)
    }

    func testPreviewContainsHistoryForAllTrendRanges() {
        XCTAssertGreaterThanOrEqual(DashboardSnapshot.preview.dailyUsage.count, 45)
    }

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

    func testQuotaAccessorsDoNotDependOnArrayIndexes() {
        let snapshot = makeSnapshot(
            quotas: Array(DashboardSnapshot.preview.quotas.reversed())
        )

        XCTAssertEqual(snapshot.fiveHourQuota?.id, "5h")
        XCTAssertEqual(snapshot.weeklyQuota?.id, "7d")
        XCTAssertEqual(snapshot.visibleQuotas.map(\.id), ["5h", "7d"])
        XCTAssertEqual(snapshot.menuBarQuotaLabel, "5H 85% · 7d 84%")
    }

    func testMissingFiveHourQuotaOnlyExposesWeeklyQuota() {
        let weeklyQuota = DashboardSnapshot.preview.quotas.first { $0.id == "7d" }!
        let snapshot = makeSnapshot(quotas: [weeklyQuota])

        XCTAssertNil(snapshot.fiveHourQuota)
        XCTAssertEqual(snapshot.visibleQuotas.map(\.id), ["7d"])
        XCTAssertEqual(snapshot.menuBarQuotaLabel, "7d 84%")
    }

    func testExhaustedFiveHourQuotaRemainsVisible() {
        let exhaustedFiveHourQuota = QuotaSnapshot(
            id: "5h",
            title: "5 小时",
            remaining: 0,
            resetText: "02:52"
        )
        let weeklyQuota = DashboardSnapshot.preview.quotas.first { $0.id == "7d" }!
        let snapshot = makeSnapshot(quotas: [exhaustedFiveHourQuota, weeklyQuota])

        XCTAssertNotNil(snapshot.fiveHourQuota)
        XCTAssertEqual(snapshot.visibleQuotas.map(\.id), ["5h", "7d"])
        XCTAssertEqual(snapshot.menuBarQuotaLabel, "5H 0% · 7d 84%")
    }

    func testMenuBarConfigurationControlsMetricAndVisibleContent() {
        let usedFiveHour = MenuBarLabelConfiguration(
            quotaDisplay: .used,
            showsFiveHour: true,
            showsWeekly: false,
            showsResetCountdown: true
        )
        let remainingWeekly = MenuBarLabelConfiguration(
            quotaDisplay: .remaining,
            showsFiveHour: false,
            showsWeekly: true,
            showsResetCountdown: true
        )

        XCTAssertEqual(
            DashboardSnapshot.preview.menuBarLabel(configuration: usedFiveHour),
            "5H 15%"
        )
        XCTAssertEqual(
            DashboardSnapshot.preview.menuBarLabel(configuration: remainingWeekly),
            "7d 84%"
        )
    }

    func testMenuBarConfigurationFallsBackWhenEveryItemIsHidden() {
        let hidden = MenuBarLabelConfiguration(
            quotaDisplay: .remaining,
            showsFiveHour: false,
            showsWeekly: false,
            showsResetCountdown: true
        )

        XCTAssertEqual(
            DashboardSnapshot.preview.menuBarLabel(configuration: hidden),
            "SpendScope"
        )
    }

    func testQuotaResetCountdownUsesCompactMinuteHourAndDayUnits() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            QuotaSnapshot(
                id: "5h", title: "5 小时", remaining: 0.8, resetText: "",
                resetsAt: now.addingTimeInterval(30 * 60)
            ).resetCountdown(now: now),
            "30m"
        )
        XCTAssertEqual(
            QuotaSnapshot(
                id: "5h", title: "5 小时", remaining: 0.8, resetText: "",
                resetsAt: now.addingTimeInterval(2 * 3_600)
            ).resetCountdown(now: now),
            "2h"
        )
        XCTAssertEqual(
            QuotaSnapshot(
                id: "7d", title: "7 天", remaining: 0.8, resetText: "",
                resetsAt: now.addingTimeInterval(6 * 86_400 + 23 * 3_600)
            ).resetCountdown(now: now),
            "6d"
        )
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

    private func makeDailyUsage(count: Int) -> [DailyUsage] {
        (1...count).map { value in
            DailyUsage(id: "\(value)", day: "\(value)", total: value)
        }
    }

    private func makeSnapshot(quotas: [QuotaSnapshot]) -> DashboardSnapshot {
        let preview = DashboardSnapshot.preview
        return DashboardSnapshot(
            planName: preview.planName,
            updatedText: preview.updatedText,
            periods: preview.periods,
            quotas: quotas,
            models: preview.models,
            dailyUsage: preview.dailyUsage
        )
    }
}
