import AppKit
import SwiftUI

struct ProjectUsagePanel: View {
    let ranking: ProjectUsageRanking

    @State private var searchText = ""
    @State private var selectedProjectID: ProjectUsageEntry.ID?
    @State private var detailWindowController: ProjectDetailWindowController?

    var body: some View {
        ZStack {
            panelContent

            if detailWindowController != nil {
                Color.black.opacity(0.12)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)
                    .transition(.opacity)
                    .accessibilityHidden(true)
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
        .animation(.easeOut(duration: 0.14), value: detailWindowController != nil)
        .onChange(of: ranking.entries) { _, entries in
            guard let selectedProjectID else { return }
            guard
                let index = entries.firstIndex(where: { $0.id == selectedProjectID }),
                let detailWindowController
            else {
                dismissProjectDetail()
                return
            }
            detailWindowController.update(entry: entries[index], rank: index + 1)
        }
        .onDisappear {
            dismissProjectDetail()
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder)
                .frame(height: 1)

            if ranking.entries.isEmpty {
                emptyState
            } else {
                tableHeader
                projectList
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SpendScopeTheme.dashboardAccent)
                .frame(width: 24, height: 24)
                .background(
                    SpendScopeTheme.dashboardAccent.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            Text("项目用量排行")
                .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 16)

            projectSearchField
            headerMetadata
        }
        .frame(height: 38)
        .padding(.horizontal, 12)
    }

    private var projectSearchField: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            TextField("搜索项目", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 9)
        .frame(width: 150, height: 26)
        .background(
            SpendScopeTheme.dashboardControlBackground.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder.opacity(0.76), lineWidth: 1)
        }
    }

    private var headerMetadata: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                Text("Token 用量")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            }

            headerSeparator

            headerMetric("项目", value: "\(ranking.projectCount)")

            headerSeparator

            headerMetric("总计", value: TokenFormatter.compact(ranking.totalTokens))
        }
        .padding(.horizontal, 9)
        .frame(height: 26, alignment: .center)
        .background(
            SpendScopeTheme.dashboardControlBackground.opacity(0.46),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder.opacity(0.62), lineWidth: 1)
        }
    }

    private var headerSeparator: some View {
        Rectangle()
            .fill(SpendScopeTheme.dashboardBorder)
            .frame(width: 1, height: 14)
    }

    private var tableHeader: some View {
        projectColumns(
            rank: "排名",
            project: "项目",
            lastActivity: "最后活动",
            conversations: "任务",
            replies: "回复",
            share: "项目占比",
            tokens: "Token",
            action: "操作",
            isHeader: true
        )
        .padding(.horizontal, 12)
        .background(SpendScopeTheme.dashboardControlBackground.opacity(0.36))
    }

    private var projectList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, minHeight: 170)
                        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                } else {
                    ForEach(filteredEntries) { rankedEntry in
                        Button {
                            presentProjectDetail(rankedEntry.entry, rank: rankedEntry.rank)
                        } label: {
                            projectRow(rankedEntry.entry, rank: rankedEntry.rank)
                        }
                        .buttonStyle(.plain)
                        .disabled(detailWindowController != nil)

                        if rankedEntry.entry.id != filteredEntries.last?.entry.id {
                            Rectangle()
                                .fill(SpendScopeTheme.dashboardBorder.opacity(0.62))
                                .frame(height: 1)
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "暂无项目用量",
            systemImage: "folder.badge.questionmark",
            description: Text("使用 Codex 后会按工作目录统计 Token。")
        )
        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
    }

    private func projectRow(_ entry: ProjectUsageEntry, rank: Int) -> some View {
        projectColumns(
            rank: "\(rank)",
            project: projectDisplayName(entry),
            lastActivity: lastActivityText(for: entry),
            conversations: "\(entry.conversations.count)",
            replies: "\(entry.conversations.reduce(0) { $0 + $1.replies.count })",
            share: TokenFormatter.percentage(entry.share),
            tokens: TokenFormatter.compact(entry.tokens),
            action: "查看详情",
            isHeader: false,
            shareValue: entry.share,
            isSelected: selectedProjectID == entry.id
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(projectAccessibilityLabel(entry, rank: rank))
        .accessibilityHint("打开项目详情窗口")
    }

    private func projectColumns(
        rank: String,
        project: String,
        lastActivity: String,
        conversations: String,
        replies: String,
        share: String,
        tokens: String,
        action: String,
        isHeader: Bool,
        shareValue: Double = 0,
        isSelected: Bool = false
    ) -> some View {
        let font: Font = isHeader
            ? .system(size: 9, weight: .semibold)
            : .system(size: 10.5, weight: .medium)
        let textColor = isHeader
            ? SpendScopeTheme.dashboardMutedText
            : SpendScopeTheme.dashboardPrimaryText.opacity(0.88)

        return HStack(spacing: 8) {
            Text(rank)
                .font(
                    isHeader
                        ? font
                        : .system(size: 10, weight: .semibold, design: .rounded)
                )
                .foregroundStyle(
                    isHeader || Int(rank, radix: 10) ?? 4 > 3
                        ? textColor
                        : SpendScopeTheme.dashboardAccent
                )
                .frame(width: 28, alignment: .center)

            HStack(spacing: 7) {
                if !isHeader {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SpendScopeTheme.dashboardAccentSecondary)
                }
                Text(project)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 164, alignment: .leading)

            Text(lastActivity)
                .monospacedDigit()
                .frame(width: 86, alignment: .leading)

            Text(conversations)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            Text(replies)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            HStack(spacing: 7) {
                if isHeader {
                    Spacer(minLength: 0)
                } else {
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
                                .frame(width: max(4, geometry.size.width * shareValue))
                        }
                        .frame(height: 5)
                        .frame(maxHeight: .infinity)
                    }
                }
                Text(share)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(minWidth: 92, maxWidth: .infinity)

            Text(tokens)
                .font(
                    isHeader
                        ? font
                        : .system(size: 10.5, weight: .semibold, design: .rounded)
                )
                .monospacedDigit()
                .frame(width: 68, alignment: .trailing)

            HStack(spacing: 3) {
                Text(action)
                if !isHeader {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .foregroundStyle(isHeader ? textColor : SpendScopeTheme.dashboardAccent)
            .frame(width: 68, alignment: .trailing)
        }
        .font(font)
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity, minHeight: isHeader ? 24 : 34)
        .padding(.horizontal, 6)
        .background(
            isSelected ? SpendScopeTheme.dashboardAccent.opacity(0.09) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private var filteredEntries: [RankedProjectUsageEntry] {
        ranking.entries.enumerated().compactMap { index, entry in
            guard
                searchText.isEmpty
                    || projectDisplayName(entry).localizedCaseInsensitiveContains(searchText)
            else {
                return nil
            }
            return RankedProjectUsageEntry(entry: entry, rank: index + 1)
        }
    }

    @MainActor
    private func presentProjectDetail(_ entry: ProjectUsageEntry, rank: Int) {
        guard detailWindowController == nil, let parentWindow = NSApp.keyWindow else { return }
        selectedProjectID = entry.id

        let controller = ProjectDetailWindowController(
            entry: entry,
            rank: rank,
            parentWindow: parentWindow
        ) {
            detailWindowController = nil
            selectedProjectID = nil
        }
        detailWindowController = controller
        controller.show()
    }

    @MainActor
    private func dismissProjectDetail() {
        detailWindowController?.dismiss()
        detailWindowController = nil
        selectedProjectID = nil
    }

    private func projectDisplayName(_ entry: ProjectUsageEntry) -> String {
        guard ranking.entries.filter({ $0.name == entry.name }).count > 1 else {
            return entry.name
        }
        return "\(entry.name) · \(entry.id.prefix(4))"
    }

    private func lastActivityText(for entry: ProjectUsageEntry) -> String {
        let milliseconds = entry.conversations.compactMap(\.lastMessageAtMilliseconds).max()
        return ProjectUsageDateFormatter.relative(milliseconds)
    }

    private func projectAccessibilityLabel(_ entry: ProjectUsageEntry, rank: Int) -> String {
        let replyCount = entry.conversations.reduce(0) { $0 + $1.replies.count }
        return "第 \(rank) 名，\(projectDisplayName(entry))，"
            + "\(TokenFormatter.compact(entry.tokens)) Token，"
            + "占比 \(TokenFormatter.percentage(entry.share))，"
            + "\(entry.conversations.count) 个任务，\(replyCount) 次回复"
    }

    private func headerMetric(_ title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 5) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardAccent)
                .monospacedDigit()
        }
    }
}

private struct RankedProjectUsageEntry: Identifiable {
    let entry: ProjectUsageEntry
    let rank: Int

    var id: ProjectUsageEntry.ID { entry.id }
}
