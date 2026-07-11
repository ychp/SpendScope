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

    private static let previewDailyUsage: [DailyUsage] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let startDate = calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 28)
        ) else {
            return []
        }

        return (0..<45).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: startDate) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard
                let year = components.year,
                let month = components.month,
                let day = components.day
            else {
                return nil
            }

            let total = 8_400_000
                + (index % 10) * 650_000
                + (index / 10) * 300_000
            return DailyUsage(
                id: String(format: "%04d-%02d-%02d", year, month, day),
                day: String(format: "%d/%d", month, day),
                total: total
            )
        }
    }()

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
        dailyUsage: previewDailyUsage
    )
}

enum TrendRange: String, CaseIterable, Identifiable, Sendable {
    case today = "今日"
    case sevenDays = "7 天"
    case thirtyDays = "30 天"
    case all = "全部"

    static let defaultRange: TrendRange = .sevenDays

    var id: Self { self }

    func select(from usage: [DailyUsage]) -> [DailyUsage] {
        let limit: Int?
        switch self {
        case .today: limit = 1
        case .sevenDays: limit = 7
        case .thirtyDays: limit = 30
        case .all: limit = nil
        }

        guard let limit else { return usage }
        return Array(usage.suffix(limit))
    }
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

    func share(of value: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(value) / Double(total), 0), 1)
    }
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
