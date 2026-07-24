import Foundation

enum CodexUsageCalendar {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = utc
        }
        return calendar
    }
}

final class DashboardQueryService: @unchecked Sendable {
    private let store: UsageStore

    init(store: UsageStore) {
        self.store = store
    }

    func snapshot(
        now: Date,
        calendar: Calendar,
        usageCalendar: Calendar? = nil,
        threadTitlesByThreadID: [String: String] = [:]
    ) throws -> DashboardSnapshot {
        let todayStart = calendar.startOfDay(for: now)
        let resolvedUsageCalendar = usageCalendar ?? calendar
        let usageTodayStart = resolvedUsageCalendar.startOfDay(for: now)
        guard
            let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: todayStart),
            let thirtyDayStart = calendar.date(byAdding: .day, value: -29, to: todayStart),
            let usageThirtyDayStart = resolvedUsageCalendar.date(
                byAdding: .day,
                value: -29,
                to: usageTodayStart
            )
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
        let sessionLastMessageTimes = try store.sessions().reduce(into: [String: Int64]()) {
            result, session in
            if let updatedAtMilliseconds = session.updatedAtMilliseconds {
                result[session.threadID] = updatedAtMilliseconds
            }
        }

        let periods = try [
            period(id: "today", title: "今日", rows: todayRows),
            period(id: "sevenDays", title: "7 日", rows: sevenDayRows),
            period(id: "thirtyDays", title: "30 日", rows: thirtyDayRows),
            period(id: "allTime", title: "累计", rows: allRows)
        ]
        let quotaResult = try quotas(now: now, calendar: calendar)
        let activityRankings = ActivityRankingSnapshot(
            today: try activityRanking(
                fromMilliseconds: milliseconds(for: todayStart),
                toMilliseconds: end
            ),
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
        let projectUsage = ProjectUsageSnapshot(
            today: try projectRanking(
                from: todayRows,
                sessionLastMessageTimes: sessionLastMessageTimes,
                threadTitlesByThreadID: threadTitlesByThreadID
            ),
            sevenDays: try projectRanking(
                from: sevenDayRows,
                sessionLastMessageTimes: sessionLastMessageTimes,
                threadTitlesByThreadID: threadTitlesByThreadID
            ),
            thirtyDays: try projectRanking(
                from: thirtyDayRows,
                sessionLastMessageTimes: sessionLastMessageTimes,
                threadTitlesByThreadID: threadTitlesByThreadID
            ),
            allTime: try projectRanking(
                from: allRows.filter { $0.observedAtMilliseconds < end },
                sessionLastMessageTimes: sessionLastMessageTimes,
                threadTitlesByThreadID: threadTitlesByThreadID
            )
        )
        let modelUsage = ModelUsageSnapshot(
            today: try modelRanking(from: todayRows),
            sevenDays: try modelRanking(from: sevenDayRows),
            thirtyDays: try modelRanking(from: thirtyDayRows),
            allTime: try modelRanking(from: allRows.filter { $0.observedAtMilliseconds < end })
        )

        return DashboardSnapshot(
            planName: resolvedPlanName(from: allRows),
            updatedText: "刚刚刷新",
            periods: periods,
            quotas: quotaResult.quotas,
            models: try models(from: sevenDayRows),
            dailyUsage: try dailyUsage(
                from: trendRows,
                minimumStart: usageThirtyDayStart,
                through: usageTodayStart,
                calendar: resolvedUsageCalendar
            ),
            activityRankings: activityRankings,
            projectUsage: projectUsage,
            modelUsage: modelUsage,
            issues: quotaResult.issues
        )
    }

    private func modelRanking(from rows: [StoredUsageQueryRow]) throws -> ModelUsageRanking {
        var totals: [String: UsageAggregate] = [:]
        var overall: Int64 = 0
        for row in rows {
            var aggregate = totals[row.model, default: UsageAggregate()]
            try aggregate.add(row, context: "model.\(row.model)")
            totals[row.model] = aggregate
            overall = try checkedAdd(overall, row.totalTokens, context: "models.total")
        }
        guard overall > 0 else { return .empty }

        let ordered = totals.sorted { left, right in
            left.value.total == right.value.total
                ? left.key < right.key
                : left.value.total > right.value.total
        }
        var estimatedCostUSD = 0.0
        var unpricedModelCount = 0
        let entries = ordered.map { model, aggregate in
            let rule = ModelPricingCatalog.rule(for: model)
            let estimatedCost = rule?.estimate(
                uncachedInputTokens: aggregate.uncachedInput,
                cachedInputTokens: aggregate.cachedInput,
                visibleOutputTokens: aggregate.visibleOutput,
                reasoningTokens: aggregate.reasoning
            )
            if let estimatedCost {
                estimatedCostUSD += estimatedCost
            } else {
                unpricedModelCount += 1
            }
            return ModelUsageEntry(
                model: model,
                totalTokens: Int(clamping: aggregate.total),
                uncachedInputTokens: Int(clamping: aggregate.uncachedInput),
                cachedInputTokens: Int(clamping: aggregate.cachedInput),
                visibleOutputTokens: Int(clamping: aggregate.visibleOutput),
                reasoningTokens: Int(clamping: aggregate.reasoning),
                share: min(max(Double(aggregate.total) / Double(overall), 0), 1),
                estimatedCostUSD: estimatedCost
            )
        }
        return ModelUsageRanking(
            entries: entries,
            totalTokens: Int(clamping: overall),
            estimatedCostUSD: estimatedCostUSD,
            unpricedModelCount: unpricedModelCount
        )
    }

    private func projectRanking(
        from rows: [StoredUsageQueryRow],
        sessionLastMessageTimes: [String: Int64],
        threadTitlesByThreadID: [String: String]
    ) throws -> ProjectUsageRanking {
        var identityGraph = ProjectUsageIdentityGraph()
        for row in rows {
            let pathNode = ProjectUsageIdentityNode(
                name: row.project.name,
                identity: "path:\(row.project.id)"
            )
            identityGraph.add(pathNode)
            if let repositoryID = row.project.repositoryID {
                identityGraph.union(
                    pathNode,
                    ProjectUsageIdentityNode(
                        name: row.project.name,
                        identity: "repository:\(repositoryID)"
                    )
                )
            }
        }

        var totals: [ProjectUsageIdentityNode: ProjectUsageAccumulator] = [:]
        var conversationTotals:
            [ProjectUsageIdentityNode: [String: ProjectConversationUsageAccumulator]] = [:]
        var overall: Int64 = 0
        for row in rows {
            let pathNode = ProjectUsageIdentityNode(
                name: row.project.name,
                identity: "path:\(row.project.id)"
            )
            let key = identityGraph.root(of: pathNode)
            let current = totals[key] ?? ProjectUsageAccumulator(
                representativePathID: row.project.id,
                tokens: 0
            )
            totals[key] = ProjectUsageAccumulator(
                representativePathID: min(current.representativePathID, row.project.id),
                tokens: try checkedAdd(current.tokens, row.totalTokens, context: "project.total")
            )
            let currentConversation = conversationTotals[key]?[row.threadID]
                ?? ProjectConversationUsageAccumulator(
                    tokens: 0,
                    lastUsageAtMilliseconds: row.observedAtMilliseconds
                )
            conversationTotals[key, default: [:]][row.threadID] =
                ProjectConversationUsageAccumulator(
                    tokens: try checkedAdd(
                        currentConversation.tokens,
                        row.totalTokens,
                        context: "project.conversation.total"
                    ),
                    lastUsageAtMilliseconds: max(
                        currentConversation.lastUsageAtMilliseconds,
                        row.observedAtMilliseconds
                    )
                )
            overall = try checkedAdd(overall, row.totalTokens, context: "projects.total")
        }
        guard overall > 0 else { return .empty }

        let ordered = totals.map { key, value in
            (key: key, id: value.representativePathID, name: key.name, tokens: value.tokens)
        }.sorted { left, right in
            if left.tokens != right.tokens { return left.tokens > right.tokens }
            if left.name != right.name { return left.name < right.name }
            return left.id < right.id
        }
        return ProjectUsageRanking(
            entries: ordered.map { entry in
                let conversations = (conversationTotals[entry.key] ?? [:]).map {
                    threadID, aggregate in
                    ProjectConversationUsage(
                        shortThreadID: ThreadDisplayIdentifier.make(from: threadID),
                        displayTitle: threadTitlesByThreadID[threadID],
                        tokens: Int(clamping: aggregate.tokens),
                        lastMessageAtMilliseconds: sessionLastMessageTimes[threadID]
                            ?? aggregate.lastUsageAtMilliseconds
                    )
                }
                return ProjectUsageEntry(
                    id: entry.id,
                    name: entry.name,
                    tokens: Int(clamping: entry.tokens),
                    share: min(max(Double(entry.tokens) / Double(overall), 0), 1),
                    conversations: ProjectConversationSortOrder.defaultOrder.sorted(conversations)
                )
            },
            totalTokens: Int(clamping: overall),
            projectCount: totals.count
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
                toMilliseconds: toMilliseconds,
                limit: 20
            ).map {
                ActivityRankingEntry(name: $0.name, count: Int(clamping: $0.count))
            },
            tools: try store.activityCounts(
                kind: .tool,
                fromMilliseconds: fromMilliseconds,
                toMilliseconds: toMilliseconds,
                limit: 20
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

private struct ProjectUsageIdentityNode: Hashable {
    let name: String
    let identity: String
}

private struct ProjectUsageIdentityGraph {
    private var parents: [ProjectUsageIdentityNode: ProjectUsageIdentityNode] = [:]

    mutating func add(_ node: ProjectUsageIdentityNode) {
        if parents[node] == nil { parents[node] = node }
    }

    mutating func union(_ left: ProjectUsageIdentityNode, _ right: ProjectUsageIdentityNode) {
        add(left)
        add(right)
        let leftRoot = root(of: left)
        let rightRoot = root(of: right)
        if leftRoot != rightRoot {
            parents[rightRoot] = leftRoot
        }
    }

    mutating func root(of node: ProjectUsageIdentityNode) -> ProjectUsageIdentityNode {
        add(node)
        guard let parent = parents[node], parent != node else { return node }
        let resolved = root(of: parent)
        parents[node] = resolved
        return resolved
    }
}

private struct ProjectUsageAccumulator {
    let representativePathID: String
    let tokens: Int64
}

private struct ProjectConversationUsageAccumulator {
    let tokens: Int64
    let lastUsageAtMilliseconds: Int64
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
