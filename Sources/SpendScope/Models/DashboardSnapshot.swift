import Foundation

struct DashboardSnapshot: Sendable {
    let planName: String
    let updatedText: String
    let periods: [PeriodUsage]
    let quotas: [QuotaSnapshot]
    let models: [ModelUsage]
    let dailyUsage: [DailyUsage]

    var todayTokens: Int { periods[0].total }
    var sevenDayTokens: Int { periods[1].total }
    var thirtyDayTokens: Int { periods[2].total }
    var totalTokens: Int { periods[3].total }

    var breakdown: TokenBreakdown {
        let today = periods[0]
        return TokenBreakdown(
            input: today.uncachedInput,
            cachedInput: today.cachedInput,
            output: today.visibleOutput,
            reasoning: today.reasoning
        )
    }

    static let preview = DashboardSnapshot(
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
            QuotaSnapshot(id: "5h", title: "5 小时", remaining: 0.85, resetText: "02:52"),
            QuotaSnapshot(
                id: "7d",
                title: "7 天",
                remaining: 0.84,
                resetText: "2026-07-13 10:45"
            )
        ],
        models: [
            ModelUsage(id: "gpt-5.5", name: "gpt-5.5", share: 0.68),
            ModelUsage(id: "gpt-5.4", name: "gpt-5.4", share: 0.32)
        ],
        dailyUsage: [
            DailyUsage(id: "5/10", day: "5/10", total: 8_400_000),
            DailyUsage(id: "5/11", day: "5/11", total: 10_300_000),
            DailyUsage(id: "5/12", day: "5/12", total: 11_100_000),
            DailyUsage(id: "5/13", day: "5/13", total: 12_500_000),
            DailyUsage(id: "5/14", day: "5/14", total: 13_700_000),
            DailyUsage(id: "5/15", day: "5/15", total: 14_200_000),
            DailyUsage(id: "5/16", day: "5/16", total: 14_000_000)
        ]
    )
}

struct PeriodUsage: Identifiable, Sendable {
    let id: String
    let title: String
    let total: Int
    let uncachedInput: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int

    var visibleOutput: Int { max(0, output - reasoning) }
}

struct QuotaSnapshot: Identifiable, Sendable {
    let id: String
    let title: String
    let remaining: Double
    let resetText: String

    var remainingPercent: Int { Int((remaining * 100).rounded()) }

    var compactTitle: String {
        switch id {
        case "5h": "5H"
        case "7d": "7d"
        default: title
        }
    }

    var remainingLabel: String {
        "\(compactTitle) \(remainingPercent)%"
    }
}

struct TokenBreakdown: Sendable {
    let input: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int

    var total: Int { input + cachedInput + output + reasoning }
}

struct ModelUsage: Identifiable, Sendable {
    let id: String
    let name: String
    let share: Double
}

struct DailyUsage: Identifiable, Sendable {
    let id: String
    let day: String
    let total: Int
}
