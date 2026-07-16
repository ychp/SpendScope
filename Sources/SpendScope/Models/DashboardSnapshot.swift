import Foundation

struct DashboardSnapshot: Sendable {
    let planName: String
    let updatedText: String
    let periods: [PeriodUsage]
    let quotas: [QuotaSnapshot]
    let models: [ModelUsage]
    let dailyUsage: [DailyUsage]
    let activityRankings: ActivityRankingSnapshot
    let issues: [DashboardIssue]

    init(
        planName: String,
        updatedText: String,
        periods: [PeriodUsage],
        quotas: [QuotaSnapshot],
        models: [ModelUsage],
        dailyUsage: [DailyUsage],
        activityRankings: ActivityRankingSnapshot = .empty,
        issues: [DashboardIssue] = []
    ) {
        self.planName = planName
        self.updatedText = updatedText
        self.periods = periods
        self.quotas = quotas
        self.models = models
        self.dailyUsage = dailyUsage
        self.activityRankings = activityRankings
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
        guard configuration.showsLivePreview else { return "SpendScope" }
        var components: [String] = []
        if configuration.showsFiveHour, let fiveHourQuota {
            components.append(fiveHourQuota.label(for: configuration.quotaDisplay))
        }
        if configuration.showsWeekly, let weeklyQuota {
            components.append(weeklyQuota.label(for: configuration.quotaDisplay))
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

enum ActivityRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays = "7 日"
    case thirtyDays = "30 日"
    case allTime = "累计"

    static let defaultRange: ActivityRange = .sevenDays

    var id: Self { self }
}

struct ActivityRankingEntry: Identifiable, Equatable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

struct ActivityRanking: Equatable, Sendable {
    let skills: [ActivityRankingEntry]
    let tools: [ActivityRankingEntry]

    static let empty = ActivityRanking(skills: [], tools: [])
}

struct ActivityRankingSnapshot: Equatable, Sendable {
    let sevenDays: ActivityRanking
    let thirtyDays: ActivityRanking
    let allTime: ActivityRanking

    static let empty = ActivityRankingSnapshot(
        sevenDays: .empty,
        thirtyDays: .empty,
        allTime: .empty
    )

    func ranking(for range: ActivityRange) -> ActivityRanking {
        switch range {
        case .sevenDays: sevenDays
        case .thirtyDays: thirtyDays
        case .allTime: allTime
        }
    }
}

enum DashboardIssue: Hashable, Sendable {
    case expiredQuota(id: String)
    case invalidQuota(id: String)
}

enum TrendRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays = "7 天"
    case thirtyDays = "30 天"

    static let defaultRange: TrendRange = .sevenDays

    var id: Self { self }

    func select(from usage: [DailyUsage]) -> [DailyUsage] {
        switch self {
        case .sevenDays:
            return Array(usage.suffix(7))
        case .thirtyDays:
            return Array(usage.suffix(30))
        }
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
    let resetsAt: Date?
    let observedAt: Date?

    init(
        id: String,
        title: String,
        remaining: Double,
        resetText: String,
        resetsAt: Date? = nil,
        observedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.remaining = remaining
        self.resetText = resetText
        self.resetsAt = resetsAt
        self.observedAt = observedAt
    }

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

    func resetCountdown(now: Date = Date()) -> String? {
        resetInterval(now: now).map { "\($0.amount)\($0.compactUnit)" }
    }

    func resetDescription(now: Date = Date()) -> String? {
        resetInterval(now: now).map { "\($0.amount) \($0.chineseUnit)后重置" }
    }

    func observationDescription(now: Date = Date()) -> String? {
        guard let observedAt else { return nil }
        let seconds = max(now.timeIntervalSince(observedAt), 0)
        if seconds < 60 { return "刚刚观测" }
        if seconds < 3_600 { return "\(max(1, Int(seconds / 60))) 分钟前观测" }
        if seconds < 86_400 { return "\(max(1, Int(seconds / 3_600))) 小时前观测" }
        return "\(max(1, Int(seconds / 86_400))) 天前观测"
    }

    private func resetInterval(now: Date) -> (amount: Int, compactUnit: String, chineseUnit: String)? {
        guard let resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }

        if seconds < 3_600 {
            return (max(1, Int(ceil(seconds / 60))), "m", "分钟")
        }
        if seconds < 86_400 {
            return (max(1, Int(ceil(seconds / 3_600))), "h", "小时")
        }
        return (max(1, Int(floor(seconds / 86_400))), "d", "天")
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
    let uncachedInput: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int

    init(
        id: String,
        day: String,
        total: Int,
        uncachedInput: Int = 0,
        cachedInput: Int = 0,
        output: Int = 0,
        reasoning: Int = 0
    ) {
        self.id = id
        self.day = day
        self.total = total
        self.uncachedInput = uncachedInput
        self.cachedInput = cachedInput
        self.output = output
        self.reasoning = reasoning
    }
}
