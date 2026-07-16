import SwiftUI

struct ActivityRankingPanel: View {
    let ranking: ActivityRanking

    var body: some View {
        HStack(spacing: 12) {
            rankingList(
                title: "Skills 排行",
                systemImage: "sparkles",
                entries: ranking.skills
            )
            rankingList(
                title: "Tools 排行",
                systemImage: "hammer",
                entries: ranking.tools
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rankingList(
        title: String,
        systemImage: String,
        entries: [ActivityRankingEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("调用次数")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            }
            .frame(height: 28)
            .padding(.horizontal, 12)

            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder)
                .frame(height: 1)

            if entries.isEmpty {
                compactEmptyState(title: title)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(6).enumerated()), id: \.element.id) { index, entry in
                        rankingRow(
                            entry,
                            rank: index + 1,
                            maximum: entries.first?.count ?? 0
                        )
                        if index < min(entries.count, 6) - 1 {
                            Rectangle()
                                .fill(SpendScopeTheme.dashboardBorder.opacity(0.72))
                                .frame(height: 1)
                                .padding(.leading, 38)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity, alignment: .top)
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

    private func rankingRow(
        _ entry: ActivityRankingEntry,
        rank: Int,
        maximum: Int
    ) -> some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    rank <= 3
                        ? SpendScopeTheme.dashboardAccent
                        : SpendScopeTheme.dashboardMutedText
                )
                .frame(width: 20, height: 20)
                .background(
                    SpendScopeTheme.dashboardControlBackground,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )

            Text(entry.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 118, alignment: .leading)
                .help(entry.name)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(SpendScopeTheme.dashboardControlBackground)
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
                        .frame(width: barWidth(
                            available: geometry.size.width,
                            count: entry.count,
                            maximum: maximum
                        ))
                }
                .frame(height: 5)
                .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 54, maxWidth: .infinity, minHeight: 20)

            Text("\(entry.count) 次")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.86))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 29)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(rank) 名，\(entry.name)，调用 \(entry.count) 次")
    }

    private func compactEmptyState(title: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardAccent.opacity(0.62))
            Text("暂无调用记录")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("\(title)暂无调用记录")
    }

    private func barWidth(available: CGFloat, count: Int, maximum: Int) -> CGFloat {
        guard maximum > 0, count > 0 else { return 0 }
        return max(5, available * CGFloat(count) / CGFloat(maximum))
    }
}
