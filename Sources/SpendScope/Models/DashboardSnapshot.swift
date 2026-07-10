import Foundation

struct DashboardSnapshot: Sendable {
    let planName: String
    let updatedText: String
    let todayTokens: Int
    let sevenDayTokens: Int
    let totalTokens: Int
    let quotas: [QuotaSnapshot]
    let breakdown: TokenBreakdown
    let models: [ModelUsage]
    let dailyUsage: [DailyUsage]

    static let preview = DashboardSnapshot(
        planName: "Pro",
        updatedText: "刚刚刷新",
        todayTokens: 17_000_000,
        sevenDayTokens: 84_200_000,
        totalTokens: 326_800_000,
        quotas: [
            QuotaSnapshot(id: "5h", title: "5 小时", remaining: 0.85, resetText: "02:52 重置"),
            QuotaSnapshot(id: "7d", title: "7 天", remaining: 0.84, resetText: "周一 10:45 重置")
        ],
        breakdown: TokenBreakdown(
            input: 8_200_000,
            cachedInput: 7_900_000,
            output: 700_000,
            reasoning: 200_000
        ),
        models: [
            ModelUsage(id: "gpt-5.5", name: "gpt-5.5", share: 0.68),
            ModelUsage(id: "gpt-5.4", name: "gpt-5.4", share: 0.32)
        ],
        dailyUsage: [
            DailyUsage(id: "5/10", day: "5/10", total: 9_800_000),
            DailyUsage(id: "5/11", day: "5/11", total: 13_100_000),
            DailyUsage(id: "5/12", day: "5/12", total: 15_000_000),
            DailyUsage(id: "5/13", day: "5/13", total: 15_700_000),
            DailyUsage(id: "5/14", day: "5/14", total: 16_300_000),
            DailyUsage(id: "5/15", day: "5/15", total: 12_900_000),
            DailyUsage(id: "5/16", day: "5/16", total: 12_100_000)
        ]
    )
}

struct QuotaSnapshot: Identifiable, Sendable {
    let id: String
    let title: String
    let remaining: Double
    let resetText: String

    var remainingPercent: Int {
        Int((remaining * 100).rounded())
    }
}

struct TokenBreakdown: Sendable {
    let input: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int

    var total: Int {
        input + cachedInput + output + reasoning
    }
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
