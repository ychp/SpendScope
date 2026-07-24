import SwiftUI

struct ProjectUsagePanel: View {
    let ranking: ProjectUsageRanking
    @State private var expandedProjectIDs: Set<ProjectUsageEntry.ID> = []
    @State private var conversationSortOrder = ProjectConversationSortOrder.defaultOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                Text("项目 Token 用量")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                summary("项目", value: "\(ranking.projectCount)")
                Rectangle()
                    .fill(SpendScopeTheme.dashboardBorder)
                    .frame(width: 1, height: 18)
                summary("总计", value: TokenFormatter.compact(ranking.totalTokens))
            }
            .frame(height: 30)
            .padding(.horizontal, 12)

            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder)
                .frame(height: 1)

            if ranking.entries.isEmpty {
                ContentUnavailableView(
                    "暂无项目用量",
                    systemImage: "folder.badge.questionmark",
                    description: Text("使用 Codex 后会按工作目录统计 Token。")
                )
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(ranking.entries.enumerated()), id: \.element.id) { index, entry in
                            projectSection(entry, rank: index + 1)
                            if index < ranking.entries.count - 1 {
                                Rectangle()
                                    .fill(SpendScopeTheme.dashboardBorder.opacity(0.72))
                                    .frame(height: 1)
                                    .padding(.leading, 42)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            SpendScopeTheme.dashboardSurfaceStrong.opacity(0.74),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder, lineWidth: 1)
        }
        .onChange(of: ranking.entries.map(\.id)) { _, availableIDs in
            expandedProjectIDs.formIntersection(availableIDs)
        }
    }

    private func projectSection(_ entry: ProjectUsageEntry, rank: Int) -> some View {
        let isExpanded = expandedProjectIDs.contains(entry.id)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    toggleProject(entry.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 24, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起 \(entry.name) 对话" : "展开 \(entry.name) 对话")
                .help(isExpanded ? "收起对话用量" : "查看项目内对话用量")

                projectRow(entry, rank: rank)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleProject(entry.id)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(projectAccessibilityLabel(entry, rank: rank))
                    .accessibilityValue(isExpanded ? "已展开" : "已折叠")
                    .accessibilityAction {
                        toggleProject(entry.id)
                    }
            }

            if isExpanded {
                conversationSection(for: entry)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func projectRow(
        _ entry: ProjectUsageEntry,
        rank: Int
    ) -> some View {
        let displayName = projectDisplayName(entry)
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    rank <= 3 ? SpendScopeTheme.dashboardAccent : SpendScopeTheme.dashboardMutedText
                )
                .frame(width: 22, height: 22)
                .background(
                    SpendScopeTheme.dashboardControlBackground,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            Image(systemName: "folder")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardAccentSecondary)

            Text(displayName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 170, alignment: .leading)
                .help(displayName)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(SpendScopeTheme.dashboardControlBackground)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    SpendScopeTheme.dashboardAccent,
                                    SpendScopeTheme.dashboardAccentSecondary
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(5, geometry.size.width * entry.share))
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 100, maxWidth: .infinity, minHeight: 22)

            Text(TokenFormatter.percentage(entry.share))
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)

            Text(TokenFormatter.compact(entry.tokens))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.9))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)

        }
        .frame(maxWidth: .infinity, minHeight: 30)
    }

    private func conversationSection(for entry: ProjectUsageEntry) -> some View {
        let sortedConversations = conversationSortOrder.sorted(entry.conversations)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(entry.conversations.count) 个对话")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                Spacer()
                Text("排序")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                conversationSortControl
            }
            .frame(height: 27)
            .padding(.leading, 44)
            .padding(.trailing, 12)

            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder.opacity(0.62))
                .frame(height: 1)
                .padding(.leading, 44)

            ForEach(sortedConversations) { conversation in
                conversationRow(conversation, projectTokens: entry.tokens)
                if conversation.id != sortedConversations.last?.id {
                    Rectangle()
                        .fill(SpendScopeTheme.dashboardBorder.opacity(0.48))
                        .frame(height: 1)
                        .padding(.leading, 76)
                }
            }
        }
        .background(SpendScopeTheme.dashboardControlBackground.opacity(0.34))
    }

    private var conversationSortControl: some View {
        HStack(spacing: 2) {
            ForEach(ProjectConversationSortOrder.allCases) { order in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        conversationSortOrder = order
                    }
                } label: {
                    Text(order == .recent ? "最近" : "用量")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            conversationSortOrder == order
                                ? SpendScopeTheme.dashboardPrimaryText
                                : SpendScopeTheme.dashboardMutedText
                        )
                        .frame(width: 38, height: 19)
                        .background(
                            conversationSortOrder == order
                                ? SpendScopeTheme.dashboardAccent.opacity(0.18)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("按\(order.rawValue)排序")
                .accessibilityAddTraits(conversationSortOrder == order ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            SpendScopeTheme.dashboardControlBackground,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder.opacity(0.72))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("对话排序")
    }

    private func conversationRow(
        _ conversation: ProjectConversationUsage,
        projectTokens: Int
    ) -> some View {
        let share = projectTokens > 0
            ? min(max(Double(conversation.tokens) / Double(projectTokens), 0), 1)
            : 0
        let displayName = conversation.displayTitle ?? conversation.shortThreadID
        let displayFont: Font = conversation.displayTitle == nil
            ? .system(size: 10, weight: .medium, design: .monospaced)
            : .system(size: 10.5, weight: .medium)
        let accessibleName = conversation.displayTitle.map {
            "\($0)，任务标识 \(conversation.shortThreadID)"
        } ?? conversation.shortThreadID
        return HStack(spacing: 10) {
            Image(systemName: "bubble.left")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardAccentSecondary)
                .frame(width: 22)

            Text(displayName)
                .font(displayFont)
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 190, alignment: .leading)
                .help(accessibleName)

            Text(lastMessageText(conversation.lastMessageAtMilliseconds))
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                .monospacedDigit()
                .frame(width: 88, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(SpendScopeTheme.dashboardControlBackground)
                    Capsule()
                        .fill(SpendScopeTheme.dashboardAccentSecondary.opacity(0.72))
                        .frame(width: max(4, geometry.size.width * share))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 80, maxWidth: .infinity, minHeight: 20)

            Text(TokenFormatter.compact(conversation.tokens))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.86))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)

            Color.clear.frame(width: 12)
        }
        .padding(.leading, 32)
        .frame(maxWidth: .infinity, minHeight: 27)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(accessibleName)，最后消息"
                + "\(lastMessageText(conversation.lastMessageAtMilliseconds))，"
                + "\(TokenFormatter.compact(conversation.tokens)) Token"
        )
    }

    private func lastMessageText(_ milliseconds: Int64?) -> String {
        guard let milliseconds else { return "时间未知" }
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'今天' HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func projectDisplayName(_ entry: ProjectUsageEntry) -> String {
        guard ranking.entries.filter({ $0.name == entry.name }).count > 1 else {
            return entry.name
        }
        return "\(entry.name) · \(entry.id.prefix(4))"
    }

    private func projectAccessibilityLabel(_ entry: ProjectUsageEntry, rank: Int) -> String {
        "第 \(rank) 名，\(projectDisplayName(entry))，"
            + "\(TokenFormatter.compact(entry.tokens)) Token，"
            + "占比 \(TokenFormatter.percentage(entry.share))，"
            + "\(entry.conversations.count) 个对话"
    }

    private func toggleProject(_ id: ProjectUsageEntry.ID) {
        withAnimation(.easeOut(duration: 0.16)) {
            if expandedProjectIDs.contains(id) {
                expandedProjectIDs.remove(id)
            } else {
                expandedProjectIDs.insert(id)
            }
        }
    }

    private func summary(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardAccent)
                .monospacedDigit()
        }
    }
}
