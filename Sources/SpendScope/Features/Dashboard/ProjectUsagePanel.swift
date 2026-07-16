import SwiftUI

struct ProjectUsagePanel: View {
    let ranking: ProjectUsageRanking

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
                            projectRow(entry, rank: index + 1)
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
    }

    private func projectRow(_ entry: ProjectUsageEntry, rank: Int) -> some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "第 \(rank) 名，\(displayName)，\(TokenFormatter.compact(entry.tokens)) Token，"
                + "占比 \(TokenFormatter.percentage(entry.share))"
        )
    }

    private func projectDisplayName(_ entry: ProjectUsageEntry) -> String {
        guard ranking.entries.filter({ $0.name == entry.name }).count > 1 else {
            return entry.name
        }
        return "\(entry.name) · \(entry.id.prefix(4))"
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
