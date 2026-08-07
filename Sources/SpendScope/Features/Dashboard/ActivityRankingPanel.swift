import SwiftUI

struct ActivityRankingPanel: View {
    let ranking: ActivityRanking
    @State private var hoveredSkillID: ActivityRankingEntry.ID?

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
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            rankingRow(
                                entry,
                                rank: index + 1,
                                maximum: entries.first?.count ?? 0
                            )
                            if index < entries.count - 1 {
                                Rectangle()
                                    .fill(SpendScopeTheme.dashboardBorder.opacity(0.72))
                                    .frame(height: 1)
                                    .padding(.leading, 38)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
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
        .contentShape(Rectangle())
        .onHover { isHovered in
            guard !entry.details.isEmpty else { return }
            if isHovered {
                hoveredSkillID = entry.id
            } else if hoveredSkillID == entry.id {
                hoveredSkillID = nil
            }
        }
        .popover(
            isPresented: hoverBinding(for: entry),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            SkillBreakdownPopover(entry: entry)
                .padding(4)
        }
        .help(
            entry.details.isEmpty
                ? entry.name
                : "悬浮查看 \(entry.name) 的细分 Skill 用量"
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(rank) 名，\(entry.name)，调用 \(entry.count) 次")
        .accessibilityHint(
            entry.details.isEmpty
                ? ""
                : "悬浮可查看 \(entry.details.count) 个细分 Skill"
        )
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

    private func hoverBinding(for entry: ActivityRankingEntry) -> Binding<Bool> {
        Binding(
            get: { !entry.details.isEmpty && hoveredSkillID == entry.id },
            set: { isPresented in
                if !isPresented, hoveredSkillID == entry.id {
                    hoveredSkillID = nil
                }
            }
        )
    }
}

private struct SkillBreakdownPopover: View {
    let entry: ActivityRankingEntry

    private var maximum: Int {
        entry.details.map(\.count).max() ?? 0
    }

    private var listHeight: CGFloat {
        min(max(CGFloat(entry.details.count) * 34, 34), 272)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(entry.details.count) 个细分 Skill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                }
                Spacer(minLength: 12)
                Text("\(entry.count) 次")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder)
                .frame(height: 1)

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(entry.details) { detail in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(detail.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help("\(entry.name):\(detail.name)")
                                Spacer(minLength: 8)
                                Text("\(detail.count) 次")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(SpendScopeTheme.dashboardControlBackground)
                                    Capsule()
                                        .fill(SpendScopeTheme.dashboardAccent)
                                        .frame(
                                            width: maximum > 0
                                                ? geometry.size.width
                                                    * CGFloat(detail.count)
                                                    / CGFloat(maximum)
                                                : 0
                                        )
                                }
                            }
                            .frame(height: 4)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(detail.name)，调用 \(detail.count) 次")
                    }
                }
            }
            .scrollIndicators(entry.details.count > 8 ? .visible : .hidden)
            .frame(height: listHeight)
        }
        .padding(12)
        .frame(width: 270)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape
                .fill(.thinMaterial)
                .overlay { shape.fill(SpendScopeTheme.glassTintStrong) }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.name) 细分 Skill 用量")
    }
}
