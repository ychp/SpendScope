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
        firstSubscriptionDate: Date? = nil,
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
        let historicalRows = allRows.filter { $0.observedAtMilliseconds < end }
        let workspaceAliases = makeWorkspaceUsageAliases(
            from: historicalRows,
            explicitAliases: try store.workspaceAliases()
        )
        let trendRows = try store.usageEvents(toMilliseconds: end)
        let allActivityRows = try store.activityEvents(toMilliseconds: end)
        let turnLifecycleFacts = makeTurnLifecycleFacts(
            from: try store.turnLifecycleEvents().filter { $0.observedAtMilliseconds < end }
        )
        let sessionLastMessageTimes = try store.sessions().reduce(into: [String: Int64]()) {
            result, session in
            if let updatedAtMilliseconds = session.updatedAtMilliseconds {
                result[session.threadID] = updatedAtMilliseconds
            }
        }

        let subscriptionCycle = firstSubscriptionDate.flatMap {
            SubscriptionCycleCalculator.cycle(
                containing: now,
                firstSubscribedAt: $0,
                calendar: calendar
            )
        }
        var periods = try [
            period(id: "today", title: "今日", rows: todayRows),
            period(id: "sevenDays", title: "7 日", rows: sevenDayRows),
            period(id: "thirtyDays", title: "30 日", rows: thirtyDayRows),
            period(id: "allTime", title: "累计", rows: allRows)
        ]
        if let subscriptionCycle {
            let subscriptionRows = try store.usageEvents(
                fromMilliseconds: milliseconds(for: subscriptionCycle.start),
                toMilliseconds: end
            )
            periods.insert(
                try period(
                    id: "subscriptionCycle",
                    title: "本订阅周期",
                    rows: subscriptionRows
                ),
                at: periods.count - 1
            )
        }
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
        let workspaceTrendDayStarts = try (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: sevenDayStart) else {
                throw DashboardQueryError.invalidCalendarBoundary
            }
            return milliseconds(for: day)
        }
        let workspaceUsage = WorkspaceUsageSnapshot(
            today: try workspaceRanking(
                from: todayRows,
                trendRows: sevenDayRows,
                trendDayStarts: workspaceTrendDayStarts,
                calendar: calendar,
                sessionLastMessageTimes: sessionLastMessageTimes,
                threadTitlesByThreadID: threadTitlesByThreadID,
                turnLifecycleFacts: turnLifecycleFacts,
                workspaceAliases: workspaceAliases,
                activityRows: allActivityRows.filter {
                    $0.observedAtMilliseconds >= milliseconds(for: todayStart)
                }
            ),
            sevenDays: try workspaceRanking(
                from: sevenDayRows,
                trendRows: sevenDayRows,
                trendDayStarts: workspaceTrendDayStarts,
                calendar: calendar,
                sessionLastMessageTimes: sessionLastMessageTimes,
                threadTitlesByThreadID: threadTitlesByThreadID,
                turnLifecycleFacts: turnLifecycleFacts,
                workspaceAliases: workspaceAliases,
                activityRows: allActivityRows.filter {
                    $0.observedAtMilliseconds >= milliseconds(for: sevenDayStart)
                }
            ),
            thirtyDays: try workspaceRanking(
                from: thirtyDayRows,
                trendRows: sevenDayRows,
                trendDayStarts: workspaceTrendDayStarts,
                calendar: calendar,
                sessionLastMessageTimes: sessionLastMessageTimes,
                threadTitlesByThreadID: threadTitlesByThreadID,
                turnLifecycleFacts: turnLifecycleFacts,
                workspaceAliases: workspaceAliases,
                activityRows: allActivityRows.filter {
                    $0.observedAtMilliseconds >= milliseconds(for: thirtyDayStart)
                }
            ),
            allTime: try workspaceRanking(
                from: historicalRows,
                trendRows: sevenDayRows,
                trendDayStarts: workspaceTrendDayStarts,
                calendar: calendar,
                sessionLastMessageTimes: sessionLastMessageTimes,
                threadTitlesByThreadID: threadTitlesByThreadID,
                turnLifecycleFacts: turnLifecycleFacts,
                workspaceAliases: workspaceAliases,
                activityRows: allActivityRows
            )
        )
        let modelUsage = ModelUsageSnapshot(
            today: try modelRanking(from: todayRows),
            sevenDays: try modelRanking(from: sevenDayRows),
            thirtyDays: try modelRanking(from: thirtyDayRows),
            allTime: try modelRanking(from: historicalRows)
        )

        return DashboardSnapshot(
            planName: resolvedPlanName(from: allRows),
            updatedText: "刚刚刷新",
            periods: periods,
            subscriptionCycle: subscriptionCycle,
            quotas: quotaResult.quotas,
            models: try models(from: sevenDayRows),
            dailyUsage: try dailyUsage(
                from: trendRows,
                minimumStart: usageThirtyDayStart,
                through: usageTodayStart,
                calendar: resolvedUsageCalendar
            ),
            subscriptionCycleUsage: try subscriptionCycleUsage(
                from: historicalRows,
                firstSubscribedAt: firstSubscriptionDate,
                through: now,
                calendar: calendar
            ),
            activityRankings: activityRankings,
            workspaceUsage: workspaceUsage,
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

    private func workspaceRanking(
        from rows: [StoredUsageQueryRow],
        trendRows: [StoredUsageQueryRow],
        trendDayStarts: [Int64],
        calendar: Calendar,
        sessionLastMessageTimes: [String: Int64],
        threadTitlesByThreadID: [String: String],
        turnLifecycleFacts: [ThreadTurnKey: TurnLifecycleFact],
        workspaceAliases: [WorkspaceUsageKey: WorkspaceUsageKey],
        activityRows: [StoredActivityEvent]
    ) throws -> WorkspaceUsageRanking {
        let turnActivityFacts = makeTurnActivityFacts(from: activityRows)
        var identityGraph = ProjectUsageIdentityGraph()
        for row in rows + trendRows {
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

        var workspaceTotals: [WorkspaceUsageKey: Int64] = [:]
        var projectTotals: [WorkspaceUsageKey: [ProjectUsageIdentityNode: ProjectUsageAccumulator]] = [:]
        var projectThreads: [WorkspaceUsageKey: [ProjectUsageIdentityNode: Set<String>]] = [:]
        var projectTurns: [WorkspaceUsageKey: [ProjectUsageIdentityNode: Set<ThreadTurnKey>]] = [:]
        var projectLastActivity: [WorkspaceUsageKey: [ProjectUsageIdentityNode: Int64]] = [:]
        var conversationTotals: [WorkspaceUsageKey: [String: ProjectConversationUsageAccumulator]] = [:]
        var dailyTotals: [WorkspaceUsageKey: [Int64: Int64]] = [:]
        var overall: Int64 = 0
        for row in rows {
            let rawWorkspaceKey = WorkspaceUsageKey(identity: row.workspace)
            let workspaceKey = workspaceAliases[rawWorkspaceKey] ?? rawWorkspaceKey
            let pathNode = ProjectUsageIdentityNode(
                name: row.project.name,
                identity: "path:\(row.project.id)"
            )
            let projectKey = identityGraph.root(of: pathNode)
            workspaceTotals[workspaceKey] = try checkedAdd(
                workspaceTotals[workspaceKey] ?? 0,
                row.totalTokens,
                context: "workspace.total"
            )
            let current = projectTotals[workspaceKey]?[projectKey] ?? ProjectUsageAccumulator(
                representativePathID: row.project.id,
                tokens: 0
            )
            projectTotals[workspaceKey, default: [:]][projectKey] = ProjectUsageAccumulator(
                representativePathID: min(current.representativePathID, row.project.id),
                tokens: try checkedAdd(current.tokens, row.totalTokens, context: "workspace.project.total")
            )
            let isIncludedInTaskMetrics = ProjectConversationUsage.isIncludedInTaskMetrics(
                displayTitle: threadTitlesByThreadID[row.threadID]
            )
            if isIncludedInTaskMetrics {
                projectThreads[workspaceKey, default: [:]][projectKey, default: []].insert(
                    row.threadID
                )
                if let turnID = row.turnID, !turnID.isEmpty {
                    projectTurns[workspaceKey, default: [:]][projectKey, default: []].insert(
                        ThreadTurnKey(threadID: row.threadID, turnID: turnID)
                    )
                }
                let activityAt = sessionLastMessageTimes[row.threadID] ?? row.observedAtMilliseconds
                projectLastActivity[workspaceKey, default: [:]][projectKey] = max(
                    projectLastActivity[workspaceKey]?[projectKey] ?? Int64.min,
                    activityAt
                )
            }
            let currentConversation = conversationTotals[workspaceKey]?[row.threadID]
                ?? ProjectConversationUsageAccumulator(
                    tokens: 0,
                    lastUsageAtMilliseconds: row.observedAtMilliseconds,
                    unattributedTokens: 0,
                    replies: [:]
                )
            var updatedConversation = currentConversation
            updatedConversation.tokens = try checkedAdd(
                currentConversation.tokens,
                row.totalTokens,
                context: "workspace.conversation.total"
            )
            updatedConversation.lastUsageAtMilliseconds = max(
                currentConversation.lastUsageAtMilliseconds,
                row.observedAtMilliseconds
            )
            if let turnID = row.turnID, !turnID.isEmpty {
                var reply = updatedConversation.replies[turnID]
                    ?? ProjectReplyUsageAccumulator(
                        model: row.model,
                        uncachedInputTokens: 0,
                        cachedInputTokens: 0,
                        visibleOutputTokens: 0,
                        reasoningTokens: 0,
                        totalTokens: 0,
                        lastUsageAtMilliseconds: row.observedAtMilliseconds
                    )
                reply.model = row.model
                reply.uncachedInputTokens = try checkedAdd(
                    reply.uncachedInputTokens,
                    row.uncachedInputTokens,
                    context: "workspace.reply.uncachedInput"
                )
                reply.cachedInputTokens = try checkedAdd(
                    reply.cachedInputTokens,
                    row.cachedInputTokens,
                    context: "workspace.reply.cachedInput"
                )
                reply.visibleOutputTokens = try checkedAdd(
                    reply.visibleOutputTokens,
                    row.visibleOutputTokens,
                    context: "workspace.reply.visibleOutput"
                )
                reply.reasoningTokens = try checkedAdd(
                    reply.reasoningTokens,
                    row.reasoningTokens,
                    context: "workspace.reply.reasoning"
                )
                reply.totalTokens = try checkedAdd(
                    reply.totalTokens,
                    row.totalTokens,
                    context: "workspace.reply.total"
                )
                reply.lastUsageAtMilliseconds = max(
                    reply.lastUsageAtMilliseconds,
                    row.observedAtMilliseconds
                )
                updatedConversation.replies[turnID] = reply
            } else {
                updatedConversation.unattributedTokens = try checkedAdd(
                    updatedConversation.unattributedTokens,
                    row.totalTokens,
                    context: "workspace.conversation.unattributed"
                )
            }
            conversationTotals[workspaceKey, default: [:]][row.threadID] = updatedConversation
            overall = try checkedAdd(overall, row.totalTokens, context: "workspaces.total")
        }

        for row in trendRows {
            let rawWorkspaceKey = WorkspaceUsageKey(identity: row.workspace)
            let workspaceKey = workspaceAliases[rawWorkspaceKey] ?? rawWorkspaceKey
            let observedDate = Date(
                timeIntervalSince1970: TimeInterval(row.observedAtMilliseconds) / 1_000
            )
            let dayStart = milliseconds(for: calendar.startOfDay(for: observedDate))
            let current = dailyTotals[workspaceKey]?[dayStart] ?? 0
            dailyTotals[workspaceKey, default: [:]][dayStart] = try checkedAdd(
                current,
                row.totalTokens,
                context: "workspace.daily"
            )
        }
        guard overall > 0 else { return .empty }

        let ordered = workspaceTotals.map { key, tokens in
            (key: key, tokens: tokens)
        }.sorted { left, right in
            if left.tokens != right.tokens { return left.tokens > right.tokens }
            if left.key.name != right.key.name { return left.key.name < right.key.name }
            return left.key.id < right.key.id
        }
        let entries = ordered.map { entry in
            let projects = (projectTotals[entry.key] ?? [:]).map { projectKey, aggregate in
                WorkspaceProjectUsageEntry(
                    id: aggregate.representativePathID,
                    name: projectKey.name,
                    tokens: Int(clamping: aggregate.tokens),
                    share: min(max(Double(aggregate.tokens) / Double(entry.tokens), 0), 1),
                    conversationCount: projectThreads[entry.key]?[projectKey]?.count ?? 0,
                    replyCount: projectTurns[entry.key]?[projectKey]?.count ?? 0,
                    lastActivityAtMilliseconds: projectLastActivity[entry.key]?[projectKey]
                )
            }.sorted { left, right in
                if left.tokens != right.tokens { return left.tokens > right.tokens }
                if left.name != right.name { return left.name < right.name }
                return left.id < right.id
            }
            let conversations = (conversationTotals[entry.key] ?? [:]).map {
                threadID, aggregate in
                let replies = aggregate.replies.map { turnID, usage in
                    let turnKey = ThreadTurnKey(threadID: threadID, turnID: turnID)
                    let lifecycle = turnLifecycleFacts[turnKey]
                    let activity = turnActivityFacts[turnKey]
                    return ProjectReplyUsage(
                        id: turnID,
                        status: lifecycle?.status ?? .unknown,
                        model: usage.model,
                        uncachedInputTokens: Int(clamping: usage.uncachedInputTokens),
                        cachedInputTokens: Int(clamping: usage.cachedInputTokens),
                        visibleOutputTokens: Int(clamping: usage.visibleOutputTokens),
                        reasoningTokens: Int(clamping: usage.reasoningTokens),
                        totalTokens: Int(clamping: usage.totalTokens),
                        startedAtMilliseconds: lifecycle?.startedAtMilliseconds,
                        endedAtMilliseconds: lifecycle?.endedAtMilliseconds,
                        lastUsageAtMilliseconds: usage.lastUsageAtMilliseconds,
                        skillCalls: activity?.skills ?? [],
                        toolCalls: activity?.tools ?? []
                    )
                }.sorted { left, right in
                    if left.displayAtMilliseconds != right.displayAtMilliseconds {
                        return left.displayAtMilliseconds > right.displayAtMilliseconds
                    }
                    return left.id < right.id
                }
                return ProjectConversationUsage(
                    shortThreadID: ThreadDisplayIdentifier.make(from: threadID),
                    displayTitle: threadTitlesByThreadID[threadID],
                    tokens: Int(clamping: aggregate.tokens),
                    lastMessageAtMilliseconds: sessionLastMessageTimes[threadID]
                        ?? aggregate.lastUsageAtMilliseconds,
                    replies: replies,
                    unattributedTokens: Int(clamping: aggregate.unattributedTokens)
                )
            }
            return WorkspaceUsageEntry(
                id: entry.key.id,
                name: entry.key.name,
                rootCount: entry.key.rootCount,
                isInferred: entry.key.isInferred,
                tokens: Int(clamping: entry.tokens),
                share: min(max(Double(entry.tokens) / Double(overall), 0), 1),
                projects: projects,
                conversations: ProjectConversationSortOrder.defaultOrder.sorted(conversations),
                dailyUsage: trendDayStarts.map { dayStart in
                    ProjectDailyUsage(
                        dayStartMilliseconds: dayStart,
                        tokens: Int(clamping: dailyTotals[entry.key]?[dayStart] ?? 0)
                    )
                }
            )
        }
        return WorkspaceUsageRanking(
            entries: entries,
            totalTokens: Int(clamping: overall),
            workspaceCount: entries.count,
            projectCount: entries.reduce(0) { $0 + $1.projects.count }
        )
    }

    private func makeWorkspaceUsageAliases(
        from rows: [StoredUsageQueryRow],
        explicitAliases: [String: String]
    ) -> [WorkspaceUsageKey: WorkspaceUsageKey] {
        var graph = WorkspaceUsageIdentityGraph()
        for row in rows {
            graph.add(row)
        }
        for sourceWorkspaceID in explicitAliases.keys.sorted() {
            guard let targetWorkspaceID = resolvedWorkspaceAliasTarget(
                for: sourceWorkspaceID,
                aliases: explicitAliases
            ) else { continue }
            graph.merge(
                sourceWorkspaceID: sourceWorkspaceID,
                into: targetWorkspaceID
            )
        }
        return graph.canonicalAliases()
    }

    private func resolvedWorkspaceAliasTarget(
        for sourceWorkspaceID: String,
        aliases: [String: String]
    ) -> String? {
        var visited: Set<String> = [sourceWorkspaceID]
        var current = sourceWorkspaceID
        while let next = aliases[current] {
            guard visited.insert(next).inserted else { return nil }
            current = next
        }
        return current == sourceWorkspaceID ? nil : current
    }

    private func makeTurnLifecycleFacts(
        from rows: [StoredTurnLifecycleQueryRow]
    ) -> [ThreadTurnKey: TurnLifecycleFact] {
        var facts: [ThreadTurnKey: TurnLifecycleFact] = [:]
        for row in rows {
            let key = ThreadTurnKey(threadID: row.threadID, turnID: row.turnID)
            var fact = facts[key] ?? TurnLifecycleFact()
            switch row.kind {
            case .started:
                fact.startedAtMilliseconds = fact.startedAtMilliseconds
                    .map { min($0, row.observedAtMilliseconds) }
                    ?? row.observedAtMilliseconds
                if fact.endedAtMilliseconds == nil {
                    fact.status = .inProgress
                }
            case .completed:
                fact.status = .completed
                fact.endedAtMilliseconds = row.observedAtMilliseconds
            case .interrupted:
                fact.status = .interrupted
                fact.endedAtMilliseconds = row.observedAtMilliseconds
            case .rolledBack:
                fact.status = .rolledBack
                fact.endedAtMilliseconds = row.observedAtMilliseconds
            }
            facts[key] = fact
        }
        return facts
    }

    private func makeTurnActivityFacts(
        from rows: [StoredActivityEvent]
    ) -> [ThreadTurnKey: TurnActivityFact] {
        var counts: [ThreadTurnKey: TurnActivityCounts] = [:]
        for row in rows {
            guard let turnID = row.turnID, !turnID.isEmpty, !row.name.isEmpty else {
                continue
            }
            let key = ThreadTurnKey(threadID: row.threadID, turnID: turnID)
            var turnCounts = counts[key] ?? TurnActivityCounts()
            switch row.kind {
            case .skill:
                turnCounts.skills[row.name, default: 0] += 1
            case .tool:
                turnCounts.tools[row.name, default: 0] += 1
            }
            counts[key] = turnCounts
        }
        return counts.mapValues { turnCounts in
            TurnActivityFact(
                skills: activityCalls(from: turnCounts.skills),
                tools: activityCalls(from: turnCounts.tools)
            )
        }
    }

    private func activityCalls(from counts: [String: Int]) -> [ProjectReplyActivityCall] {
        counts.map { name, count in
            ProjectReplyActivityCall(name: name, count: count)
        }
        .sorted { left, right in
            if left.count != right.count { return left.count > right.count }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private func activityRanking(
        fromMilliseconds: Int64?,
        toMilliseconds: Int64
    ) throws -> ActivityRanking {
        let skillCounts = try store.activityCounts(
            kind: .skill,
            fromMilliseconds: fromMilliseconds,
            toMilliseconds: toMilliseconds,
            limit: nil
        )
        return ActivityRanking(
            skills: try groupedSkillRanking(from: skillCounts),
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

    private func groupedSkillRanking(
        from counts: [StoredActivityCount],
        limit: Int = 20
    ) throws -> [ActivityRankingEntry] {
        struct Group {
            var total: Int64 = 0
            var standalone: Int64 = 0
            var details: [String: Int64] = [:]
        }

        var groups: [String: Group] = [:]
        for item in counts {
            let parts = item.name.split(
                separator: ":",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            let hasNamespace = parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
            let groupName = hasNamespace ? String(parts[0]) : item.name
            var group = groups[groupName] ?? Group()
            group.total = try checkedAdd(
                group.total,
                item.count,
                context: "activity.skills.\(groupName)"
            )
            if hasNamespace {
                group.details[String(parts[1])] = item.count
            } else {
                group.standalone = try checkedAdd(
                    group.standalone,
                    item.count,
                    context: "activity.skills.\(groupName).standalone"
                )
            }
            groups[groupName] = group
        }

        return groups.map { name, group in
            var details = group.details.map { detailName, count in
                ActivityRankingDetail(name: detailName, count: Int(clamping: count))
            }
            if !details.isEmpty, group.standalone > 0 {
                details.append(
                    ActivityRankingDetail(
                        name: "直接使用",
                        count: Int(clamping: group.standalone)
                    )
                )
            }
            details.sort { left, right in
                if left.count != right.count { return left.count > right.count }
                return left.name < right.name
            }
            return ActivityRankingEntry(
                name: name,
                count: Int(clamping: group.total),
                details: details
            )
        }
        .sorted { left, right in
            if left.count != right.count { return left.count > right.count }
            return left.name < right.name
        }
        .prefix(limit)
        .map { $0 }
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

    private func subscriptionCycleUsage(
        from rows: [StoredUsageQueryRow],
        firstSubscribedAt: Date?,
        through now: Date,
        calendar: Calendar
    ) throws -> [DailyUsage] {
        guard let firstSubscribedAt, firstSubscribedAt <= now else { return [] }

        var totals: [Date: UsageAggregate] = [:]
        var modelTotals: [Date: [String: UsageAggregate]] = [:]
        for row in rows {
            let observedAt = Date(
                timeIntervalSince1970: TimeInterval(row.observedAtMilliseconds) / 1_000
            )
            guard let cycle = SubscriptionCycleCalculator.cycle(
                containing: observedAt,
                firstSubscribedAt: firstSubscribedAt,
                calendar: calendar
            ) else {
                continue
            }
            var aggregate = totals[cycle.start, default: UsageAggregate()]
            try aggregate.add(row, context: "subscriptionCycle")
            totals[cycle.start] = aggregate

            var cycleModelTotals = modelTotals[cycle.start, default: [:]]
            var modelAggregate = cycleModelTotals[row.model, default: UsageAggregate()]
            try modelAggregate.add(row, context: "subscriptionCycle.\(row.model)")
            cycleModelTotals[row.model] = modelAggregate
            modelTotals[cycle.start] = cycleModelTotals
        }

        var result: [DailyUsage] = []
        var cycleIndex = 0
        while true {
            guard let start = calendar.date(
                byAdding: .month,
                value: cycleIndex,
                to: firstSubscribedAt
            ), start <= now,
            let end = calendar.date(
                byAdding: .month,
                value: cycleIndex + 1,
                to: firstSubscribedAt
            ), end > start else {
                break
            }
            let aggregate = totals[start, default: UsageAggregate()]
            let costEstimate = subscriptionCycleCostEstimate(
                from: modelTotals[start, default: [:]]
            )
            result.append(DailyUsage(
                id: subscriptionCycleID(for: start, calendar: calendar),
                day: subscriptionCycleLabel(start: start, end: end, calendar: calendar),
                total: Int(clamping: aggregate.total),
                uncachedInput: Int(clamping: aggregate.uncachedInput),
                cachedInput: Int(clamping: aggregate.cachedInput),
                output: Int(clamping: aggregate.visibleOutput),
                reasoning: Int(clamping: aggregate.reasoning),
                estimatedCostUSD: costEstimate.usd,
                unpricedModelCount: costEstimate.unpricedModelCount
            ))
            cycleIndex += 1
        }
        return result
    }

    private func subscriptionCycleCostEstimate(
        from modelTotals: [String: UsageAggregate]
    ) -> (usd: Double, unpricedModelCount: Int) {
        var estimatedCostUSD = 0.0
        var unpricedModelCount = 0
        for (model, aggregate) in modelTotals {
            guard let rule = ModelPricingCatalog.rule(for: model) else {
                unpricedModelCount += 1
                continue
            }
            estimatedCostUSD += rule.estimate(
                uncachedInputTokens: aggregate.uncachedInput,
                cachedInputTokens: aggregate.cachedInput,
                visibleOutputTokens: aggregate.visibleOutput,
                reasoningTokens: aggregate.reasoning
            )
        }
        return (estimatedCostUSD, unpricedModelCount)
    }

    private func subscriptionCycleID(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private func subscriptionCycleLabel(start: Date, end: Date, calendar: Calendar) -> String {
        let startComponents = calendar.dateComponents([.month, .day], from: start)
        let endComponents = calendar.dateComponents([.month, .day], from: end)
        return String(
            format: "%d/%d–%d/%d",
            startComponents.month ?? 0,
            startComponents.day ?? 0,
            endComponents.month ?? 0,
            endComponents.day ?? 0
        )
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

        for kind in [QuotaKind.weekly] {
            guard let observation = byKind[kind] else { continue }
            let id = "7d"
            let expectedWindowMinutes = 10_080
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
                title: "7 天",
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

private struct WorkspaceUsageKey: Hashable {
    let id: String
    let name: String
    let rootCount: Int
    let isInferred: Bool

    init(identity: WorkspaceIdentity) {
        id = identity.id
        name = identity.name
        rootCount = identity.rootCount
        isInferred = identity.isInferred
    }
}

private struct WorkspaceUsageMergeAnchor: Hashable {
    let workspaceName: String
    let identity: String
}

private struct WorkspaceUsageIdentityGraph {
    private var parents: [WorkspaceUsageKey: WorkspaceUsageKey] = [:]
    private var workspaceByAnchor: [WorkspaceUsageMergeAnchor: WorkspaceUsageKey] = [:]
    private var workspacesByID: [String: Set<WorkspaceUsageKey>] = [:]
    private var repositoryBackedWorkspaces: Set<WorkspaceUsageKey> = []
    private var explicitTargets: Set<WorkspaceUsageKey> = []

    mutating func add(_ row: StoredUsageQueryRow) {
        let workspace = WorkspaceUsageKey(identity: row.workspace)
        add(workspace)
        workspacesByID[workspace.id, default: []].insert(workspace)

        if let repositoryID = row.project.repositoryID, !repositoryID.isEmpty {
            repositoryBackedWorkspaces.insert(workspace)
        }
        guard workspace.id != WorkspaceIdentity.unknown.id,
              workspace.name != WorkspaceIdentity.unknown.name,
              workspace.rootCount == 1,
              !workspace.isInferred else { return }

        if row.project.id != ProjectIdentity.unknown.id {
            union(
                workspace,
                through: WorkspaceUsageMergeAnchor(
                    workspaceName: workspace.name,
                    identity: "path:\(row.project.id)"
                )
            )
        }
        if let repositoryID = row.project.repositoryID, !repositoryID.isEmpty {
            union(
                workspace,
                through: WorkspaceUsageMergeAnchor(
                    workspaceName: workspace.name,
                    identity: "repository:\(repositoryID)"
                )
            )
        }
    }

    mutating func merge(sourceWorkspaceID: String, into targetWorkspaceID: String) {
        guard let sources = workspacesByID[sourceWorkspaceID],
              let targets = workspacesByID[targetWorkspaceID],
              !sources.isEmpty,
              !targets.isEmpty else { return }
        for source in sources {
            for target in targets {
                union(source, target)
            }
        }
        explicitTargets.formUnion(targets)
    }

    mutating func canonicalAliases() -> [WorkspaceUsageKey: WorkspaceUsageKey] {
        var membersByRoot: [WorkspaceUsageKey: [WorkspaceUsageKey]] = [:]
        for workspace in Array(parents.keys) {
            membersByRoot[root(of: workspace), default: []].append(workspace)
        }

        var aliases: [WorkspaceUsageKey: WorkspaceUsageKey] = [:]
        for members in membersByRoot.values {
            guard let representative = members.sorted(by: isPreferredRepresentative).first else {
                continue
            }
            for workspace in members {
                aliases[workspace] = representative
            }
        }
        return aliases
    }

    private mutating func add(_ workspace: WorkspaceUsageKey) {
        if parents[workspace] == nil { parents[workspace] = workspace }
    }

    private mutating func union(
        _ workspace: WorkspaceUsageKey,
        through anchor: WorkspaceUsageMergeAnchor
    ) {
        guard let existing = workspaceByAnchor[anchor] else {
            workspaceByAnchor[anchor] = workspace
            return
        }
        union(existing, workspace)
    }

    private mutating func union(_ left: WorkspaceUsageKey, _ right: WorkspaceUsageKey) {
        let leftRoot = root(of: left)
        let rightRoot = root(of: right)
        if leftRoot != rightRoot {
            parents[rightRoot] = leftRoot
        }
    }

    private mutating func root(of workspace: WorkspaceUsageKey) -> WorkspaceUsageKey {
        add(workspace)
        guard let parent = parents[workspace], parent != workspace else { return workspace }
        let resolved = root(of: parent)
        parents[workspace] = resolved
        return resolved
    }

    private func isPreferredRepresentative(
        _ left: WorkspaceUsageKey,
        _ right: WorkspaceUsageKey
    ) -> Bool {
        let leftIsExplicitTarget = explicitTargets.contains(left)
        let rightIsExplicitTarget = explicitTargets.contains(right)
        if leftIsExplicitTarget != rightIsExplicitTarget {
            return leftIsExplicitTarget
        }
        let leftHasRepository = repositoryBackedWorkspaces.contains(left)
        let rightHasRepository = repositoryBackedWorkspaces.contains(right)
        if leftHasRepository != rightHasRepository {
            return leftHasRepository
        }
        if left.id != right.id { return left.id < right.id }
        if left.name != right.name { return left.name < right.name }
        if left.rootCount != right.rootCount { return left.rootCount < right.rootCount }
        return !left.isInferred && right.isInferred
    }
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
    var tokens: Int64
    var lastUsageAtMilliseconds: Int64
    var unattributedTokens: Int64
    var replies: [String: ProjectReplyUsageAccumulator]
}

private struct ProjectReplyUsageAccumulator {
    var model: String
    var uncachedInputTokens: Int64
    var cachedInputTokens: Int64
    var visibleOutputTokens: Int64
    var reasoningTokens: Int64
    var totalTokens: Int64
    var lastUsageAtMilliseconds: Int64
}

private struct ThreadTurnKey: Hashable {
    let threadID: String
    let turnID: String
}

private struct TurnLifecycleFact {
    var status: ProjectReplyUsageStatus = .unknown
    var startedAtMilliseconds: Int64?
    var endedAtMilliseconds: Int64?
}

private struct TurnActivityFact {
    let skills: [ProjectReplyActivityCall]
    let tools: [ProjectReplyActivityCall]
}

private struct TurnActivityCounts {
    var skills: [String: Int] = [:]
    var tools: [String: Int] = [:]
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
