import Foundation

struct DashboardSnapshot: Sendable {
    let planName: String
    let updatedText: String
    let periods: [PeriodUsage]
    let quotas: [QuotaSnapshot]
    let models: [ModelUsage]
    let dailyUsage: [DailyUsage]
    let issues: [DashboardIssue]

    init(
        planName: String,
        updatedText: String,
        periods: [PeriodUsage],
        quotas: [QuotaSnapshot],
        models: [ModelUsage],
        dailyUsage: [DailyUsage],
        issues: [DashboardIssue] = []
    ) {
        self.planName = planName
        self.updatedText = updatedText
        self.periods = periods
        self.quotas = quotas
        self.models = models
        self.dailyUsage = dailyUsage
        self.issues = issues
    }

    var todayTokens: Int { period(id: "today").total }
    var sevenDayTokens: Int { period(id: "sevenDays").total }
    var thirtyDayTokens: Int { period(id: "thirtyDays").total }
    var totalTokens: Int { period(id: "allTime").total }

    var fiveHourQuota: QuotaSnapshot? {
        quotas.first { $0.id == "5h" }
    }

    var weeklyQuota: QuotaSnapshot? {
        quotas.first { $0.id == "7d" }
    }

    var visibleQuotas: [QuotaSnapshot] {
        [fiveHourQuota, weeklyQuota].compactMap { $0 }
    }

    var menuBarQuotaLabel: String {
        menuBarLabel(configuration: .standard)
    }

    func menuBarLabel(configuration: MenuBarLabelConfiguration) -> String {
        var components: [String] = []
        if configuration.showsFiveHour, let fiveHourQuota {
            components.append(fiveHourQuota.label(for: configuration.quotaDisplay))
        }
        if configuration.showsWeekly, let weeklyQuota {
            components.append(weeklyQuota.label(for: configuration.quotaDisplay))
        }
        if configuration.showsToday {
            components.append("今日 \(TokenFormatter.compact(todayTokens))")
        }
        return components.isEmpty ? "SpendScope" : components.joined(separator: " · ")
    }

    var breakdown: TokenBreakdown {
        let today = period(id: "today")
        return TokenBreakdown(
            input: today.uncachedInput,
            cachedInput: today.cachedInput,
            output: today.visibleOutput,
            reasoning: today.reasoning
        )
    }

    static func empty(updatedText: String) -> DashboardSnapshot {
        DashboardSnapshot(
            planName: "Free",
            updatedText: updatedText,
            periods: [
                zeroPeriod(id: "today", title: "今日"),
                zeroPeriod(id: "sevenDays", title: "7 日"),
                zeroPeriod(id: "thirtyDays", title: "30 日"),
                zeroPeriod(id: "allTime", title: "累计")
            ],
            quotas: [],
            models: [],
            dailyUsage: []
        )
    }

    private func period(id: String) -> PeriodUsage {
        periods.first { $0.id == id } ?? Self.zeroPeriod(id: id, title: "")
    }

    private static func zeroPeriod(id: String, title: String) -> PeriodUsage {
        PeriodUsage(
            id: id, title: title, total: 0, uncachedInput: 0,
            cachedInput: 0, output: 0, reasoning: 0
        )
    }

}

enum DashboardIssue: Hashable, Sendable {
    case expiredQuota(id: String)
    case invalidQuota(id: String)
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

    func label(for preference: QuotaDisplayPreference) -> String {
        let percent: Int
        switch preference {
        case .used:
            percent = Int(((1 - remaining) * 100).rounded())
        case .remaining:
            percent = remainingPercent
        }
        return "\(compactTitle) \(percent)%"
    }
}

struct TokenBreakdown: Sendable {
    let input: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int

    var total: Int {
        [input, cachedInput, output, reasoning].reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? Int.max : sum
        }
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
