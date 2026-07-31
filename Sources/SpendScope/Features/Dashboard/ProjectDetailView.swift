import Charts
import SwiftUI

struct ProjectDetailView: View {
    let entry: ProjectUsageEntry
    let rank: Int
    let onClose: () -> Void
    let onReplyHover: (ProjectReplyDetailRow?) -> Void

    @State private var selectedTab: ProjectDetailTab = .overview
    @State private var conversationSortOrder = ProjectConversationSortOrder.defaultOrder
    @State private var conversationSearchText = ""
    @State private var hoveredTrendDayID: Int64?

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    projectHeader
                    tabSelector
                    summaryCards

                    switch selectedTab {
                    case .overview:
                        overviewContent
                    case .conversations:
                        conversationDetailList
                    case .replies:
                        replyTable
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.visible)

            footer
        }
        .frame(minWidth: 720, minHeight: 520)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(
                    colors: [
                        SpendScopeTheme.dashboardAccent.opacity(0.045),
                        SpendScopeTheme.dashboardSurfaceStrong.opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .foregroundStyle(SpendScopeTheme.dashboardPrimaryText)
        .onDisappear {
            onReplyHover(nil)
        }
        .onExitCommand(perform: onClose)
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText.opacity(0.55))
                Text("项目详情")
                    .font(.system(size: 12, weight: .semibold))
            }

            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("关闭项目详情")
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 40, alignment: .center)
        .background(SpendScopeTheme.dashboardSurfaceOpaque)
        .contentShape(Rectangle())
    }

    private var projectHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "link")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [
                            SpendScopeTheme.dashboardAccentSecondary,
                            SpendScopeTheme.dashboardAccent
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .shadow(color: SpendScopeTheme.dashboardAccent.opacity(0.22), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(entry.name)
                        .font(.system(size: 21, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("排行 #\(rank)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpendScopeTheme.dashboardAccent)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            SpendScopeTheme.dashboardAccent.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(SpendScopeTheme.dashboardAccent.opacity(0.34), lineWidth: 1)
                        }
                }
                Text("最近活动 \(ProjectUsageDateFormatter.relative(lastActivityMilliseconds))")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            }

            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var summaryCards: some View {
        HStack(spacing: 10) {
            metricCard(
                "总 Token",
                value: TokenFormatter.compact(entry.tokens),
                icon: "number.square.fill",
                tint: SpendScopeTheme.dashboardAccent
            )
            metricCard(
                "项目占比",
                value: TokenFormatter.percentage(entry.share),
                icon: "chart.pie.fill",
                tint: SpendScopeTheme.dashboardInput
            )
            metricCard(
                "任务",
                value: "\(visibleConversations.count)",
                icon: "list.bullet.rectangle.fill",
                tint: SpendScopeTheme.dashboardAccentSecondary
            )
            metricCard(
                "回复",
                value: "\(replyRows.count)",
                icon: "ellipsis.bubble.fill",
                tint: SpendScopeTheme.accent
            )
        }
    }

    private func metricCard(
        _ title: String,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(
            SpendScopeTheme.dashboardTile.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder, lineWidth: 1)
        }
        .shadow(color: SpendScopeTheme.dashboardShadow.opacity(0.6), radius: 5, y: 2)
    }

    private var tabSelector: some View {
        HStack(spacing: 28) {
            ForEach(ProjectDetailTab.allCases) { tab in
                Button {
                    if tab != .replies {
                        onReplyHover(nil)
                    }
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(
                            selectedTab == tab
                                ? SpendScopeTheme.dashboardAccent
                                : SpendScopeTheme.dashboardMutedText
                        )

                        Capsule()
                            .fill(
                                selectedTab == tab
                                    ? SpendScopeTheme.dashboardAccent
                                    : Color.clear
                            )
                            .frame(width: selectedTab == tab ? 34 : 0, height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder)
                .frame(height: 1)
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 12) {
                    tokenBreakdownCard
                        .frame(width: max(300, (geometry.size.width - 12) * 0.44))
                    trendCard
                }
            }
            .frame(height: 148)
            conversationTable
        }
    }

    private var tokenBreakdownCard: some View {
        let segments = tokenSegments
        let visualTotal = segments.reduce(0.0) { result, segment in
            result + (segment.value > 0 ? max(segment.share, 0.014) : 0)
        }

        return detailCard(title: "Token 构成", icon: "chart.bar.xaxis", height: 148) {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        ForEach(segments) { segment in
                            segment.color
                                .frame(
                                    width: segment.value > 0 && visualTotal > 0
                                        ? max(
                                            0,
                                            (geometry.size.width - 3)
                                                * max(segment.share, 0.014)
                                                / visualTotal
                                        )
                                        : 0
                                )
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
                .background(
                    SpendScopeTheme.dashboardControlBackground,
                    in: Capsule()
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 6
                ) {
                    ForEach(segments) { segment in
                        tokenSegmentCell(segment)
                    }
                }
            }
        }
    }

    private func tokenSegmentCell(_ segment: ProjectTokenSegment) -> some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(segment.color)
                .frame(width: 3, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(segment.title)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(TokenFormatter.percentage(segment.share))
                        .monospacedDigit()
                }
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)

                Text(TokenFormatter.compact(segment.value))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.90))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            segment.color.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private var trendCard: some View {
        detailCard(title: "近 7 日趋势", icon: "chart.xyaxis.line", height: 148) {
            Chart(entry.dailyUsage) { point in
                AreaMark(
                    x: .value("日期", point.date),
                    y: .value("Token", point.tokens)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            SpendScopeTheme.dashboardAccent.opacity(0.24),
                            SpendScopeTheme.dashboardAccent.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("日期", point.date),
                    y: .value("Token", point.tokens)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(SpendScopeTheme.dashboardAccent)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                if point.tokens > 0 {
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("Token", point.tokens)
                    )
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                    .symbolSize(18)
                }

                if hoveredTrendDayID == point.id {
                    RuleMark(x: .value("悬停日期", point.date))
                        .foregroundStyle(SpendScopeTheme.dashboardAccent.opacity(0.36))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    PointMark(
                        x: .value("悬停日期", point.date),
                        y: .value("悬停 Token", point.tokens)
                    )
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                    .symbolSize(54)
                }
            }
            .chartYScale(domain: 0...trendYAxisMaximum)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                        .foregroundStyle(SpendScopeTheme.dashboardGrid)
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(TokenFormatter.compact(tokens))
                        }
                    }
                }
            }
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case let .active(location):
                                    guard let plotFrame = proxy.plotFrame else {
                                        hoveredTrendDayID = nil
                                        return
                                    }
                                    let plotRect = geometry[plotFrame]
                                    guard plotRect.contains(location) else {
                                        hoveredTrendDayID = nil
                                        return
                                    }
                                    let plotX = location.x - plotRect.minX
                                    guard let date: Date = proxy.value(atX: plotX) else {
                                        hoveredTrendDayID = nil
                                        return
                                    }
                                    hoveredTrendDayID = entry.dailyUsage.min {
                                        abs($0.date.timeIntervalSince(date))
                                            < abs($1.date.timeIntervalSince(date))
                                    }?.id
                                case .ended:
                                    hoveredTrendDayID = nil
                                }
                            }

                        if
                            let point = hoveredTrendPoint,
                            let plotFrame = proxy.plotFrame,
                            let pointX = proxy.position(forX: point.date)
                        {
                            let plotRect = geometry[plotFrame]
                            let tooltipHalfWidth: CGFloat = 55
                            let tooltipX = min(
                                max(
                                    plotRect.minX + pointX,
                                    plotRect.minX + tooltipHalfWidth
                                ),
                                plotRect.maxX - tooltipHalfWidth
                            )

                            trendTooltip(for: point)
                                .frame(width: tooltipHalfWidth * 2, alignment: .leading)
                                .position(
                                    x: tooltipX,
                                    y: plotRect.minY + 26
                                )
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .frame(height: 92)
        }
    }

    private func trendTooltip(for point: ProjectDailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(
                point.date,
                format: .dateTime
                    .month(.defaultDigits)
                    .day(.defaultDigits)
                    .weekday(.abbreviated)
            )
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(SpendScopeTheme.dashboardMutedText)

            Text(TokenFormatter.compact(point.tokens))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()

            Text("7 日占比 \(TokenFormatter.percentage(trendShare(for: point)))")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            SpendScopeTheme.dashboardSurfaceOpaque,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder, lineWidth: 1)
        }
        .shadow(color: SpendScopeTheme.dashboardShadow, radius: 6, y: 2)
    }

    private var conversationTable: some View {
        conversationListCard(title: "任务用量")
    }

    private var conversationDetailList: some View {
        conversationListCard(title: "任务明细")
    }

    private func conversationListCard(title: String) -> some View {
        detailCard(
            title: title,
            icon: "list.bullet.rectangle",
            titleAccessory: {
                conversationSearchField
            },
            trailing: {
                conversationSortMenu
            }
        ) {
            conversationListContent
        }
    }

    @ViewBuilder
    private var conversationListContent: some View {
        if sortedConversations.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText.opacity(0.68))
                Text("没有找到匹配的任务")
                    .font(.system(size: 11, weight: .semibold))
                Text("换个关键词试试")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
        } else {
            LazyVStack(spacing: 7) {
                ForEach(Array(sortedConversations.enumerated()), id: \.element.id) {
                    index,
                    conversation in
                    conversationDetailRow(conversation, position: index + 1)
                }
            }
        }
    }

    private func conversationDetailRow(
        _ conversation: ProjectConversationUsage,
        position: Int
    ) -> some View {
        let title = conversation.displayTitle ?? conversation.shortThreadID
        let share = entry.tokens > 0
            ? min(max(Double(conversation.tokens) / Double(entry.tokens), 0), 1)
            : 0

        return HStack(alignment: .center, spacing: 12) {
            Text("\(position)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardAccent)
                .monospacedDigit()
                .frame(width: 28, height: 28)
                .background(
                    SpendScopeTheme.dashboardAccent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.91))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Label(
                        ProjectUsageDateFormatter.relative(
                            conversation.lastMessageAtMilliseconds
                        ),
                        systemImage: "clock"
                    )
                    Label(
                        "\(conversation.replies.count) 次回复",
                        systemImage: "bubble.left"
                    )
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            }

            VStack(alignment: .trailing, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(TokenFormatter.compact(conversation.tokens))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.92))
                        .monospacedDigit()
                    Text("Token")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                }

                HStack(spacing: 7) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(SpendScopeTheme.dashboardControlBackground)
                            Capsule()
                                .fill(SpendScopeTheme.dashboardAccentSecondary)
                                .frame(
                                    width: max(
                                        share > 0 ? 4 : 0,
                                        geometry.size.width * share
                                    )
                                )
                        }
                    }
                    .frame(width: 88, height: 5)

                    Text(TokenFormatter.percentage(share))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .frame(width: 158, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            SpendScopeTheme.dashboardControlBackground.opacity(0.34),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder.opacity(0.72), lineWidth: 1)
        }
        .help(
            conversation.displayTitle.map {
                "\($0) · 任务标识 \(conversation.shortThreadID)"
            } ?? conversation.shortThreadID
        )
    }

    private var conversationSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            TextField("搜索任务", text: $conversationSearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 9)
        .frame(width: 190, height: 28)
        .background(
            SpendScopeTheme.dashboardControlBackground.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder.opacity(0.76), lineWidth: 1)
        }
    }

    private var conversationSortMenu: some View {
        Menu {
            Button {
                conversationSortOrder = .recent
            } label: {
                Label(
                    "按最近活动",
                    systemImage: conversationSortOrder == .recent
                        ? "checkmark.circle.fill"
                        : "clock"
                )
            }
            Button {
                conversationSortOrder = .usage
            } label: {
                Label(
                    "按 Token 用量",
                    systemImage: conversationSortOrder == .usage
                        ? "checkmark.circle.fill"
                        : "number.square"
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                Text(conversationSortOrder == .recent ? "按最近活动" : "按 Token 用量")
                    .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.88))
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                    .frame(width: 16, height: 16)
                    .background(
                        SpendScopeTheme.dashboardSurfaceStrong.opacity(0.72),
                        in: Circle()
                    )
            }
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 132, height: 28)
        .background(
            SpendScopeTheme.dashboardControlBackground.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    SpendScopeTheme.dashboardBorder.opacity(0.88),
                    lineWidth: 1
                )
        }
        .shadow(
            color: SpendScopeTheme.dashboardShadow.opacity(0.28),
            radius: 2,
            y: 1
        )
        .help("切换任务排序方式")
    }

    private var replyTable: some View {
        detailCard(title: "回复明细", icon: "bubble.left.and.text.bubble.right") {
            if replyRows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(SpendScopeTheme.dashboardMutedText.opacity(0.68))
                    Text("暂无回复记录")
                        .font(.system(size: 11, weight: .semibold))
                    Text("该项目还没有可展示的回复")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(replyRows) { row in
                        replyRow(row)
                    }
                }
            }
        }
    }

    private func replyRow(_ row: ProjectReplyDetailRow) -> some View {
        let status = ProjectReplyPresentation.status(row.reply.status)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: ProjectReplyPresentation.icon(row.reply.status))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status.color)
                .frame(width: 30, height: 30)
                .background(
                    status.color.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 7) {
                Text(row.conversationTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.91))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Label(
                        ProjectUsageDateFormatter.replyTime(
                            row.reply.displayAtMilliseconds
                        ),
                        systemImage: "clock"
                    )

                    Text(status.title)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(status.color)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(
                            status.color.opacity(0.09),
                            in: Capsule()
                        )

                    Label(
                        row.reply.model.isEmpty ? "模型未知" : row.reply.model,
                        systemImage: "cpu"
                    )
                    .lineLimit(1)
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            }

            VStack(alignment: .trailing, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(TokenFormatter.compact(row.reply.totalTokens))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.92))
                        .monospacedDigit()
                    Text("Token")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                }

                HStack(spacing: 7) {
                    Label(
                        ProjectUsageDateFormatter.duration(
                            row.reply.durationMilliseconds
                        ),
                        systemImage: "stopwatch"
                    )
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                    .monospacedDigit()

                    replyActivityMetric(
                        title: "Skill",
                        count: row.reply.skillCallCount,
                        icon: "sparkles",
                        tint: SpendScopeTheme.dashboardInput
                    )
                    replyActivityMetric(
                        title: "工具",
                        count: row.reply.toolCallCount,
                        icon: "wrench.and.screwdriver.fill",
                        tint: SpendScopeTheme.dashboardAccentSecondary
                    )
                }
            }
            .frame(width: 210, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            SpendScopeTheme.dashboardControlBackground.opacity(0.34),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder.opacity(0.72), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            onReplyHover(isHovering ? row : nil)
        }
    }

    private func replyActivityMetric(
        title: String,
        count: Int,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .semibold))
            Text("\(title) \(count)")
                .monospacedDigit()
        }
        .font(.system(size: 8.5, weight: .semibold))
        .foregroundStyle(count > 0 ? tint : SpendScopeTheme.dashboardMutedText.opacity(0.72))
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(
            (count > 0 ? tint : SpendScopeTheme.dashboardMutedText).opacity(0.08),
            in: Capsule()
        )
    }

    private func detailCard<Content: View>(
        title: String,
        icon: String,
        height: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        detailCard(
            title: title,
            icon: icon,
            height: height,
            titleAccessory: { EmptyView() },
            trailing: { EmptyView() },
            content: content
        )
    }

    private func detailCard<Trailing: View, Content: View>(
        title: String,
        icon: String,
        height: CGFloat? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        detailCard(
            title: title,
            icon: icon,
            height: height,
            titleAccessory: { EmptyView() },
            trailing: trailing,
            content: content
        )
    }

    private func detailCard<TitleAccessory: View, Trailing: View, Content: View>(
        title: String,
        icon: String,
        height: CGFloat? = nil,
        @ViewBuilder titleAccessory: () -> TitleAccessory,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.92))
                titleAccessory()
                Spacer()
                trailing()
            }
            content()
        }
        .padding(13)
        .frame(
            maxWidth: .infinity,
            minHeight: height,
            maxHeight: height,
            alignment: .topLeading
        )
        .background(
            SpendScopeTheme.dashboardTile.opacity(0.86),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder, lineWidth: 1)
        }
        .shadow(color: SpendScopeTheme.dashboardShadow.opacity(0.52), radius: 6, y: 2)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder)
                .frame(height: 1)
            HStack {
                Spacer()
                Button(action: onClose) {
                    Text("完成")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 78, height: 28)
                        .background(
                            LinearGradient(
                                colors: [
                                    SpendScopeTheme.dashboardAccentSecondary,
                                    SpendScopeTheme.dashboardAccent
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                        }
                        .shadow(
                            color: SpendScopeTheme.dashboardAccent.opacity(0.22),
                            radius: 5,
                            y: 2
                        )
                }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
        }
        .background(SpendScopeTheme.dashboardSurfaceStrong.opacity(0.80))
    }

    private var sortedConversations: [ProjectConversationUsage] {
        let filtered = visibleConversations.filter { conversation in
            guard !conversationSearchText.isEmpty else { return true }
            return (conversation.displayTitle ?? conversation.shortThreadID)
                .localizedCaseInsensitiveContains(conversationSearchText)
                || conversation.shortThreadID.localizedCaseInsensitiveContains(conversationSearchText)
        }
        return conversationSortOrder.sorted(filtered)
    }

    private var replyRows: [ProjectReplyDetailRow] {
        visibleConversations.flatMap { conversation in
            let title = conversation.displayTitle ?? conversation.shortThreadID
            return conversation.replies.map {
                ProjectReplyDetailRow(
                    id: "\(conversation.id)-\($0.id)",
                    conversationTitle: title,
                    reply: $0
                )
            }
        }
        .sorted {
            if $0.reply.displayAtMilliseconds != $1.reply.displayAtMilliseconds {
                return $0.reply.displayAtMilliseconds > $1.reply.displayAtMilliseconds
            }
            return $0.id < $1.id
        }
    }

    private var visibleConversations: [ProjectConversationUsage] {
        entry.conversations.filter { conversation in
            let title = conversation.displayTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title != "命令权限检查"
        }
    }

    private var tokenSegments: [ProjectTokenSegment] {
        let totals = entry.conversations
            .flatMap(\.replies)
            .reduce(into: (input: 0, cached: 0, output: 0, reasoning: 0)) { result, reply in
                result.input += reply.uncachedInputTokens
                result.cached += reply.cachedInputTokens
                result.output += reply.visibleOutputTokens
                result.reasoning += reply.reasoningTokens
            }
        let total = max(totals.input + totals.cached + totals.output + totals.reasoning, 1)
        return [
            ProjectTokenSegment(
                id: "input",
                title: "输入",
                value: totals.input,
                share: Double(totals.input) / Double(total),
                color: SpendScopeTheme.dashboardInput
            ),
            ProjectTokenSegment(
                id: "cached",
                title: "缓存输入",
                value: totals.cached,
                share: Double(totals.cached) / Double(total),
                color: SpendScopeTheme.dashboardCachedInput
            ),
            ProjectTokenSegment(
                id: "output",
                title: "输出",
                value: totals.output,
                share: Double(totals.output) / Double(total),
                color: SpendScopeTheme.output
            ),
            ProjectTokenSegment(
                id: "reasoning",
                title: "推理",
                value: totals.reasoning,
                share: Double(totals.reasoning) / Double(total),
                color: SpendScopeTheme.reasoning
            )
        ]
    }

    private var lastActivityMilliseconds: Int64? {
        visibleConversations.compactMap(\.lastMessageAtMilliseconds).max()
    }

    private var trendYAxisMaximum: Int {
        max(1, Int(Double(entry.dailyUsage.map(\.tokens).max() ?? 0) * 1.08))
    }

    private var hoveredTrendPoint: ProjectDailyUsage? {
        guard let hoveredTrendDayID else { return nil }
        return entry.dailyUsage.first { $0.id == hoveredTrendDayID }
    }

    private func trendShare(for point: ProjectDailyUsage) -> Double {
        let total = entry.dailyUsage.reduce(0) { $0 + $1.tokens }
        guard total > 0 else { return 0 }
        return Double(point.tokens) / Double(total)
    }
}

struct ProjectReplyHoverCard: View {
    let row: ProjectReplyDetailRow

    var body: some View {
        let status = ProjectReplyPresentation.status(row.reply.status)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: ProjectReplyPresentation.icon(row.reply.status))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.color)
                    .frame(width: 30, height: 30)
                    .background(status.color.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("回复调用详情")
                        .font(.system(size: 13, weight: .semibold))
                    Text(
                        ProjectUsageDateFormatter.replyTime(
                            row.reply.displayAtMilliseconds
                        )
                    )
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                    .monospacedDigit()
                }
                Spacer()
                Text(status.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .background(status.color.opacity(0.09), in: Capsule())
            }

            HStack(spacing: 9) {
                hoverSummary(
                    title: "Skills",
                    count: row.reply.skillCallCount,
                    icon: "sparkles",
                    tint: SpendScopeTheme.dashboardInput
                )
                hoverSummary(
                    title: "Tools",
                    count: row.reply.toolCallCount,
                    icon: "wrench.and.screwdriver.fill",
                    tint: SpendScopeTheme.dashboardAccentSecondary
                )
            }

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    activitySection(
                        title: "Skills 调用",
                        icon: "sparkles",
                        tint: SpendScopeTheme.dashboardInput,
                        calls: row.reply.skillCalls
                    )
                    activitySection(
                        title: "Tools 调用",
                        icon: "wrench.and.screwdriver.fill",
                        tint: SpendScopeTheme.dashboardAccentSecondary,
                        calls: row.reply.toolCalls
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 110, maxHeight: 420)
            .scrollIndicators(.visible)

            Divider()

            Text(
                "Token  输入 \(TokenFormatter.compact(row.reply.uncachedInputTokens))"
                    + " · 缓存 \(TokenFormatter.compact(row.reply.cachedInputTokens))"
                    + " · 输出 \(TokenFormatter.compact(row.reply.visibleOutputTokens))"
                    + " · 推理 \(TokenFormatter.compact(row.reply.reasoningTokens))"
            )
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            .monospacedDigit()
        }
        .padding(16)
        .frame(width: 410)
        .background(
            SpendScopeTheme.dashboardSurfaceOpaque,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder, lineWidth: 1)
        }
        .foregroundStyle(SpendScopeTheme.dashboardPrimaryText)
    }

    private func hoverSummary(
        title: String,
        count: Int,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            Spacer(minLength: 0)
            Text("\(count) 次")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(
            tint.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func activitySection(
        title: String,
        icon: String,
        tint: Color,
        calls: [ProjectReplyActivityCall]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)

            if calls.isEmpty {
                Text("本次回复未调用")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            } else {
                ForEach(calls) { call in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tint.opacity(0.72))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(call.name)
                            .font(.system(size: 10, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text("\(call.count) 次")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                            .monospacedDigit()
                            .padding(.top, 1)
                    }
                    .frame(minHeight: 20)
                }
            }
        }
    }
}

private enum ProjectDetailTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case conversations = "任务明细"
    case replies = "回复明细"

    var id: Self { self }

    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2.fill"
        case .conversations: "list.bullet.rectangle"
        case .replies: "bubble.left.and.text.bubble.right"
        }
    }
}

struct ProjectReplyDetailRow: Identifiable {
    let id: String
    let conversationTitle: String
    let reply: ProjectReplyUsage
}

private struct ProjectTokenSegment: Identifiable {
    let id: String
    let title: String
    let value: Int
    let share: Double
    let color: Color
}

private extension ProjectDailyUsage {
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(dayStartMilliseconds) / 1_000)
    }
}

enum ProjectUsageDateFormatter {
    static func relative(_ milliseconds: Int64?) -> String {
        guard let milliseconds else { return "时间未知" }
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'今天' HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func replyTime(_ milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm:ss" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func duration(_ milliseconds: Int64?) -> String {
        guard let milliseconds else { return "—" }
        if milliseconds < 1_000 { return "\(milliseconds)ms" }
        let seconds = Double(milliseconds) / 1_000
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        return String(format: "%dm%02ds", Int(seconds) / 60, Int(seconds) % 60)
    }
}

enum ProjectReplyPresentation {
    static func status(
        _ status: ProjectReplyUsageStatus
    ) -> (title: String, color: Color) {
        switch status {
        case .completed: ("完成", .green)
        case .interrupted: ("中断", .orange)
        case .rolledBack: ("回滚", .orange)
        case .inProgress: ("进行中", SpendScopeTheme.dashboardAccent)
        case .unknown: ("未知", SpendScopeTheme.dashboardMutedText)
        }
    }

    static func icon(_ status: ProjectReplyUsageStatus) -> String {
        switch status {
        case .completed: "checkmark"
        case .interrupted: "exclamationmark"
        case .rolledBack: "arrow.uturn.backward"
        case .inProgress: "ellipsis"
        case .unknown: "questionmark"
        }
    }
}
