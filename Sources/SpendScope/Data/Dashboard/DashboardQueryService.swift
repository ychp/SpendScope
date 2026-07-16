import Foundation

final class DashboardQueryService: @unchecked Sendable {
    private let store: UsageStore

    init(store: UsageStore) {
        self.store = store
    }

    func snapshot(now: Date, calendar: Calendar) throws -> DashboardSnapshot {
        let todayStart = calendar.startOfDay(for: now)
        guard
            let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: todayStart),
            let thirtyDayStart = calendar.date(byAdding: .day, value: -29, to: todayStart)
        else {
            throw DashboardQueryError.invalidCalendarBoundary
        }

        let end = exclusiveEndMilliseconds(for: now)
        let todayRows = try store.usageEvents(
            fromMilliseconds: milliseconds(for: todayStart), toMilliseconds: end
        )
        let sevenDayRows = try store.usageEvents(
            fromMilliseconds: milliseconds(for: sevenDayStart), toMilliseconds: end
        )
        let thirtyDayRows = try store.usageEvents(
            fromMilliseconds: milliseconds(for: thirtyDayStart), toMilliseconds: end
        )
        let allRows = try store.usageEvents()
        let trendRows = try store.usageEvents(toMilliseconds: end)

        let periods = try [
            period(id: "today", title: "今日", rows: todayRows),
            period(id: "sevenDays", title: "7 日", rows: sevenDayRows),
            period(id: "thirtyDays", title: "30 日", rows: thirtyDayRows),
            period(id: "allTime", title: "累计", rows: allRows)
        ]
        let quotaResult = try quotas(now: now, calendar: calendar)
        let activityRankings = ActivityRankingSnapshot(
            sevenDays: try activityRanking(
                fromMilliseconds: milliseconds(for: sevenDayStart),
                toMilliseconds: end
            ),
            thirtyDays: try activityRanking(
                fromMilliseconds: milliseconds(for: thirtyDayStart),
                toMilliseconds: end
            ),
            allTime: try activityRanking(fromMilliseconds: nil, toMilliseconds: end)
        )

        return DashboardSnapshot(
            planName: resolvedPlanName(from: allRows),
            updatedText: "刚刚刷新",
            periods: periods,
            quotas: quotaResult.quotas,
            models: try models(from: sevenDayRows),
            dailyUsage: try dailyUsage(
                from: trendRows,
                minimumStart: thirtyDayStart,
                through: todayStart,
                calendar: calendar
            ),
            activityRankings: activityRankings,
            issues: quotaResult.issues
        )
    }

    private func activityRanking(
        fromMilliseconds: Int64?,
        toMilliseconds: Int64
    ) throws -> ActivityRanking {
        ActivityRanking(
            skills: try store.activityCounts(
                kind: .skill,
                fromMilliseconds: fromMilliseconds,
                toMilliseconds: toMilliseconds
            ).map {
                ActivityRankingEntry(name: $0.name, count: Int(clamping: $0.count))
            },
            tools: try store.activityCounts(
                kind: .tool,
                fromMilliseconds: fromMilliseconds,
                toMilliseconds: toMilliseconds
            ).map {
                ActivityRankingEntry(name: $0.name, count: Int(clamping: $0.count))
            }
        )
    }

    private func period(
        id: String,
        title: String,
        rows: [StoredUsageQueryRow]
    ) throws -> PeriodUsage {
        let aggregate = try UsageAggregate(rows: rows)
        return PeriodUsage(
            id: id,
            title: title,
            total: Int(clamping: aggregate.total),
            uncachedInput: Int(clamping: aggregate.uncachedInput),
            cachedInput: Int(clamping: aggregate.cachedInput),
            output: Int(clamping: try checkedAdd(
                aggregate.visibleOutput, aggregate.reasoning, context: "period.raw_output"
            )),
            reasoning: Int(clamping: aggregate.reasoning)
        )
    }

    private func models(from rows: [StoredUsageQueryRow]) throws -> [ModelUsage] {
        var totals: [String: Int64] = [:]
        var overall: Int64 = 0
        for row in rows {
            totals[row.model] = try checkedAdd(
                totals[row.model, default: 0], row.totalTokens, context: "model.total"
            )
            overall = try checkedAdd(overall, row.totalTokens, context: "models.total")
        }
        guard overall > 0 else { return [] }

        let ordered = totals.sorted { left, right in
            left.value == right.value ? left.key < right.key : left.value > right.value
        }
        var remainingShare = 1.0
        return ordered.map { name, total in
            let rawShare = Double(total) / Double(overall)
            let share = min(max(rawShare, 0), remainingShare)
            remainingShare = max(remainingShare - share, 0)
            return ModelUsage(id: name, name: name, share: share)
        }
    }

    private func dailyUsage(
        from rows: [StoredUsageQueryRow],
        minimumStart: Date,
        through endDay: Date,
        calendar: Calendar
    ) throws -> [DailyUsage] {
        guard !rows.isEmpty else { return [] }

        var totals: [Date: UsageAggregate] = [:]
        var earliestDay = minimumStart
        for row in rows {
            let date = Date(timeIntervalSince1970: TimeInterval(row.observedAtMilliseconds) / 1_000)
            let day = calendar.startOfDay(for: date)
            if day < earliestDay { earliestDay = day }
            var aggregate = totals[day, default: UsageAggregate()]
            try aggregate.add(row, context: "daily")
            totals[day] = aggregate
        }

        var result: [DailyUsage] = []
        var day = earliestDay
        while day <= endDay {
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = components.year, let month = components.month, let dayNumber = components.day else {
                throw DashboardQueryError.invalidCalendarBoundary
            }
            let aggregate = totals[day, default: UsageAggregate()]
            result.append(DailyUsage(
                id: String(format: "%04d-%02d-%02d", year, month, dayNumber),
                day: String(format: "%d/%d", month, dayNumber),
                total: Int(clamping: aggregate.total),
                uncachedInput: Int(clamping: aggregate.uncachedInput),
                cachedInput: Int(clamping: aggregate.cachedInput),
                output: Int(clamping: aggregate.visibleOutput),
                reasoning: Int(clamping: aggregate.reasoning)
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else {
                throw DashboardQueryError.invalidCalendarBoundary
            }
            day = next
        }
        return result
    }

    private func quotas(
        now: Date,
        calendar: Calendar
    ) throws -> (quotas: [QuotaSnapshot], issues: [DashboardIssue]) {
        let latest = try store.latestQuotas()
        let byKind = Dictionary(uniqueKeysWithValues: latest.map { ($0.observation.kind, $0.observation) })
        let nowMilliseconds = milliseconds(for: now)
        var snapshots: [QuotaSnapshot] = []
        var issues: [DashboardIssue] = []

        for kind in [QuotaKind.fiveHour, .weekly] {
            guard let observation = byKind[kind] else { continue }
            let id = kind == .fiveHour ? "5h" : "7d"
            let expectedWindowMinutes = kind == .fiveHour ? 300 : 10_080
            guard observation.windowMinutes == expectedWindowMinutes,
                  observation.remaining.isFinite, (0...1).contains(observation.remaining),
                  let resetsAt = observation.resetsAtMilliseconds else {
                issues.append(.invalidQuota(id: id))
                continue
            }
            guard resetsAt > nowMilliseconds else {
                issues.append(.expiredQuota(id: id))
                continue
            }
            snapshots.append(QuotaSnapshot(
                id: id,
                title: kind == .fiveHour ? "5 小时" : "7 天",
                remaining: observation.remaining,
                resetText: QuotaResetFormatter.string(
                    resetsAtMilliseconds: resetsAt, now: now, calendar: calendar
                ),
                resetsAt: Date(timeIntervalSince1970: TimeInterval(resetsAt) / 1_000),
                observedAt: Date(
                    timeIntervalSince1970: TimeInterval(observation.observedAtMilliseconds) / 1_000
                )
            ))
        }
        return (snapshots, issues)
    }

    private func resolvedPlanName(from rows: [StoredUsageQueryRow]) -> String {
        let plan = rows
            .filter { !$0.plan.isInferred }
            .max {
                if $0.observedAtMilliseconds != $1.observedAtMilliseconds {
                    return $0.observedAtMilliseconds < $1.observedAtMilliseconds
                }
                return $0.fingerprint < $1.fingerprint
            }?.plan.kind ?? .free
        return plan.displayName
    }

    private func milliseconds(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }

    private func exclusiveEndMilliseconds(for date: Date) -> Int64 {
        let value = milliseconds(for: date)
        return value == Int64.max ? value : value + 1
    }
}

enum DashboardQueryError: Error, Equatable {
    case invalidCalendarBoundary
    case tokenOverflow(context: String)
}

enum QuotaResetFormatter {
    static func string(
        resetsAtMilliseconds: Int64,
        now: Date,
        calendar: Calendar
    ) -> String {
        let resetDate = Date(
            timeIntervalSince1970: TimeInterval(resetsAtMilliseconds) / 1_000
        )
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDate(resetDate, inSameDayAs: now) ? "HH:mm" : "MM-dd"
        return formatter.string(from: resetDate)
    }
}

private struct UsageAggregate {
    var uncachedInput: Int64 = 0
    var cachedInput: Int64 = 0
    var visibleOutput: Int64 = 0
    var reasoning: Int64 = 0
    var total: Int64 = 0

    init() {}

    init(rows: [StoredUsageQueryRow]) throws {
        for row in rows {
            try add(row, context: "usage")
        }
    }

    mutating func add(_ row: StoredUsageQueryRow, context: String) throws {
        uncachedInput = try checkedAdd(uncachedInput, row.uncachedInputTokens, context: "\(context).uncached")
        cachedInput = try checkedAdd(cachedInput, row.cachedInputTokens, context: "\(context).cached")
        visibleOutput = try checkedAdd(visibleOutput, row.visibleOutputTokens, context: "\(context).visible")
        reasoning = try checkedAdd(reasoning, row.reasoningTokens, context: "\(context).reasoning")
        total = try checkedAdd(total, row.totalTokens, context: "\(context).total")
    }
}

private func checkedAdd(_ left: Int64, _ right: Int64, context: String) throws -> Int64 {
    let (sum, overflow) = left.addingReportingOverflow(right)
    guard !overflow else { throw DashboardQueryError.tokenOverflow(context: context) }
    return sum
}

private extension PlanKind {
    var displayName: String {
        switch self {
        case .free: "Free"
        case .plus: "Plus"
        case .proLite: "Pro 5x"
        case .pro20x: "Pro 20x"
        }
    }
}
