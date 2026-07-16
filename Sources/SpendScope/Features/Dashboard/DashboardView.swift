import Charts
import SwiftUI

struct DashboardView: View {
    let store: DashboardStore

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                unavailableView(
                    "正在载入 Codex 数据",
                    systemImage: "chart.bar.doc.horizontal",
                    description: "SpendScope 正在读取已保存的本地统计。"
                )
            case .loaded(let snapshot, _):
                DashboardContentView(snapshot: snapshot)
            case .empty:
                unavailableView(
                    "未检测到 Codex 数据",
                    systemImage: "tray",
                    description: "使用 Codex 后刷新即可在这里查看 Token 用量。"
                )
            case .stale(let snapshot, _, let message):
                DashboardContentView(snapshot: snapshot)
                    .overlay(alignment: .topTrailing) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 22)
                            .padding(.trailing, 16)
                    }
            case .failed(let message):
                unavailableView(
                    "暂时无法载入数据",
                    systemImage: "exclamationmark.triangle",
                    description: message
                )
            case .unsupported(let message):
                unavailableView(
                    "Codex 数据格式暂不兼容",
                    systemImage: "doc.badge.ellipsis",
                    description: message
                )
            }
        }
        .task { await store.start() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .opacity(store.isRefreshing ? 0 : 1)

                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: 16, height: 16)
                }
                .disabled(store.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel(store.isRefreshing ? "正在刷新" : "刷新")
                .help(store.isRefreshing ? "正在刷新" : "刷新")

                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .help("设置")
            }
        }
    }

    private func unavailableView(
        _ title: String,
        systemImage: String,
        description: String
    ) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(minWidth: 920, minHeight: 620)
        .background(SpendScopeTheme.dashboardBackground)
    }
}

private struct DashboardContentView: View {
    let snapshot: DashboardSnapshot
    @State private var selectedRange = TrendRange.defaultRange
    @State private var hoveredUsageID: DailyUsage.ID?

    var body: some View {
        ZStack {
            dashboardBackground

            VStack(alignment: .leading, spacing: 14) {
                dashboardHeader
                overviewPanel.frame(height: 238)
                trendRow.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
        }
        .frame(minWidth: 920, minHeight: 620)
        .foregroundStyle(SpendScopeTheme.dashboardPrimaryText)
    }

    private var dashboardBackground: some View {
        SpendScopeTheme.dashboardBackground
            .overlay(alignment: .topLeading) {
                RadialGradient(
                    colors: [
                        SpendScopeTheme.dashboardAccent.opacity(0.075),
                        SpendScopeTheme.dashboardAccentSecondary.opacity(0.025),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 12,
                    endRadius: 560
                )
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }

    private var dashboardHeader: some View {
        Text("Codex · \(snapshot.planName)  ·  \(snapshot.updatedText)")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
    }

    private var overviewPanel: some View {
        HStack(spacing: 16) {
            currentQuotaSection.frame(width: 280)
            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder)
                .frame(width: 1)
            periodMetricsSection
        }
        .dashboardPanel(padding: 14, strong: true)
    }

    private var currentQuotaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("额度使用", systemImage: "gauge.with.dots.needle.50percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText)

            if snapshot.visibleQuotas.isEmpty {
                ContentUnavailableView(
                    "暂无额度数据",
                    systemImage: "chart.donut"
                )
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            } else {
                VStack(spacing: 5) {
                    quotaRingGroup
                    quotaResetList
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func quotaColor(for quota: QuotaSnapshot) -> Color {
        quota.id == "7d" ? SpendScopeTheme.dashboardAccent : SpendScopeTheme.dashboardAccentSecondary
    }

    private var quotaRingGroup: some View {
        ZStack {
            ForEach(snapshot.visibleQuotas) { quota in
                quotaRing(
                    quota,
                    diameter: quotaDiameter(for: quota),
                    lineWidth: quotaLineWidth(for: quota),
                    color: quotaColor(for: quota)
                )
            }

            if snapshot.visibleQuotas.count == 1,
               let quota = snapshot.visibleQuotas.first {
                quotaCenterLabel(quota)
            } else {
                if let weeklyQuota = snapshot.weeklyQuota {
                    quotaCenterLabel(weeklyQuota)
                }
                if let fiveHourQuota = snapshot.fiveHourQuota {
                    quotaOuterLabel(fiveHourQuota)
                        .offset(y: -56)
                }
            }
        }
        .frame(width: 132, height: 122)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("剩余额度")
    }

    private func quotaDiameter(for quota: QuotaSnapshot) -> CGFloat {
        guard snapshot.visibleQuotas.count > 1 else { return 112 }
        return quota.id == "5h" ? 112 : 86
    }

    private func quotaLineWidth(for quota: QuotaSnapshot) -> CGFloat {
        guard snapshot.visibleQuotas.count > 1 else { return 6 }
        return quota.id == "5h" ? 4.5 : 6.5
    }

    private func quotaCenterLabel(_ quota: QuotaSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(quota.compactTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(quotaColor(for: quota))
            Text("\(quota.remainingPercent)%")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quota.remainingLabel)
    }

    private func quotaOuterLabel(_ quota: QuotaSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(quota.compactTitle)
                .font(.system(size: 10, weight: .semibold))
            Text("\(quota.remainingPercent)%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(quotaColor(for: quota))
        .padding(.horizontal, 7)
        .background(SpendScopeTheme.dashboardSurfaceStrong)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quota.remainingLabel)
    }

    private func quotaRing(
        _ quota: QuotaSnapshot,
        diameter: CGFloat,
        lineWidth: CGFloat,
        color: Color
    ) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.28), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: quota.remaining)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.68), color, color.opacity(0.82)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private var quotaResetList: some View {
        VStack(spacing: 0) {
            ForEach(snapshot.visibleQuotas) { quota in
                quotaResetRow(quota, color: quotaColor(for: quota))

                if quota.id != snapshot.visibleQuotas.last?.id {
                    Rectangle()
                        .fill(SpendScopeTheme.dashboardBorder)
                        .frame(height: 1)
                }
            }
        }
        .frame(maxWidth: 200)
    }

    private func quotaResetRow(_ quota: QuotaSnapshot, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text("\(quota.compactTitle) 重置")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.8))

            Spacer(minLength: 8)

            Text(quota.resetText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.86))
                .monospacedDigit()
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(quota.compactTitle) 重置 \(quota.resetText)")
    }

    private var periodGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var periodMetricsSection: some View {
        LazyVGrid(columns: periodGridColumns, spacing: 10) {
            ForEach(snapshot.periods) { period in
                periodTile(period)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func periodTile(_ period: PeriodUsage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: periodIcon(for: period))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                    .frame(width: 26, height: 26)
                    .background(
                        SpendScopeTheme.dashboardAccent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                Text(period.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.88))
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(TokenFormatter.compact(period.total))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(SpendScopeTheme.dashboardPrimaryText)
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }

            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder.opacity(0.82))
                .frame(height: 1)

            periodMetricMatrix(period)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            SpendScopeTheme.dashboardTile,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder)
        }
        .shadow(color: SpendScopeTheme.dashboardShadow.opacity(0.55), radius: 6, y: 2)
    }

    private func periodMetricMatrix(_ period: PeriodUsage) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                periodMetric(
                    "输入",
                    value: period.uncachedInput,
                    share: period.share(of: period.uncachedInput),
                    color: SpendScopeTheme.dashboardInput
                )
                .padding(.trailing, 10)

                periodMetricVerticalDivider

                periodMetric(
                    "缓存",
                    value: period.cachedInput,
                    share: period.share(of: period.cachedInput),
                    color: SpendScopeTheme.dashboardCachedInput
                )
                .padding(.leading, 10)
            }
            .frame(maxHeight: .infinity)

            Rectangle()
                .fill(SpendScopeTheme.dashboardBorder.opacity(0.72))
                .frame(height: 1)

            HStack(spacing: 0) {
                periodMetric(
                    "输出",
                    value: period.visibleOutput,
                    share: period.share(of: period.visibleOutput),
                    color: SpendScopeTheme.output
                )
                .padding(.trailing, 10)

                periodMetricVerticalDivider

                periodMetric(
                    "推理",
                    value: period.reasoning,
                    share: period.share(of: period.reasoning),
                    color: SpendScopeTheme.reasoning
                )
                .padding(.leading, 10)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var periodMetricVerticalDivider: some View {
        Rectangle()
            .fill(SpendScopeTheme.dashboardBorder.opacity(0.72))
            .frame(width: 1)
            .padding(.vertical, 2)
    }

    private func periodIcon(for period: PeriodUsage) -> String {
        switch period.id {
        case "today": "calendar"
        case "sevenDays": "calendar"
        case "thirtyDays": "calendar.badge.clock"
        default: "chart.bar.fill"
        }
    }

    private func periodMetric(
        _ title: String,
        value: Int,
        share: Double,
        color: Color
    ) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            Spacer(minLength: 3)
            Text(TokenFormatter.compact(value))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardPrimaryText.opacity(0.88))
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(title) \(TokenFormatter.compact(value))，占当前周期 \(TokenFormatter.percentage(share))"
        )
    }

    private var selectedUsage: [DailyUsage] {
        selectedRange.select(from: snapshot.dailyUsage)
    }

    private var selectedTotal: Int {
        selectedUsage.reduce(0) { partial, item in
            let (sum, overflow) = partial.addingReportingOverflow(item.total)
            return overflow ? Int.max : sum
        }
    }

    private var selectedAverage: Int {
        guard !selectedUsage.isEmpty else { return 0 }
        return selectedTotal / selectedUsage.count
    }

    private var hoveredUsage: DailyUsage? {
        guard let hoveredUsageID else { return nil }
        return selectedUsage.first { $0.id == hoveredUsageID }
    }

    private var trendUpperBound: Int {
        let maximum = selectedUsage.map(\.total).max() ?? 0
        return max(1, maximum + max(maximum / 5, 1))
    }

    private var trendRow: some View {
        HStack(spacing: 14) {
            UsageCalendarPanel(usage: snapshot.dailyUsage)
                .frame(width: 300)
            trendPanel
        }
    }

    private var trendPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Token 趋势", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 14, weight: .semibold))

                rangeSelector

                Spacer()

                HStack(spacing: 16) {
                    trendSummary("总计", value: selectedTotal)
                    Rectangle()
                        .fill(SpendScopeTheme.dashboardBorder)
                        .frame(width: 1, height: 24)
                    trendSummary("日均", value: selectedAverage)
                }
            }

            Chart(selectedUsage) { item in
                AreaMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            SpendScopeTheme.dashboardAccent.opacity(0.34),
                            SpendScopeTheme.dashboardAccentSecondary.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(SpendScopeTheme.dashboardAccent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(SpendScopeTheme.dashboardAccent)
                .symbolSize(24)

                if hoveredUsage?.id == item.id {
                    RuleMark(x: .value("悬停日期", item.day))
                        .foregroundStyle(SpendScopeTheme.dashboardAccent.opacity(0.28))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    PointMark(
                        x: .value("悬停日期", item.day),
                        y: .value("悬停 Token", item.total)
                    )
                    .foregroundStyle(Color.white)
                    .symbolSize(86)

                    PointMark(
                        x: .value("悬停日期", item.day),
                        y: .value("悬停 Token", item.total)
                    )
                    .foregroundStyle(SpendScopeTheme.dashboardAccent)
                    .symbolSize(46)
                    .annotation(
                        position: Double(item.total) / Double(trendUpperBound) > 0.72 ? .bottom : .top,
                        spacing: 8
                    ) {
                        DailyUsageHoverCard(usage: item, dateText: item.day)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(SpendScopeTheme.dashboardGrid)
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(TokenFormatter.compact(tokens))
                                .font(.system(size: 10))
                                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisTick().foregroundStyle(SpendScopeTheme.dashboardGrid)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(SpendScopeTheme.dashboardMutedText)
                }
            }
            .chartYScale(domain: 0...trendUpperBound)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(SpendScopeTheme.dashboardPrimaryText.opacity(0.001))
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                updateHoveredUsage(
                                    at: location,
                                    proxy: proxy,
                                    geometry: geometry
                                )
                            case .ended:
                                hoveredUsageID = nil
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dashboardPanel(padding: 14)
    }

    private var rangeSelector: some View {
        HStack(spacing: 2) {
            ForEach(TrendRange.allCases) { range in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        hoveredUsageID = nil
                        selectedRange = range
                    }
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 11, weight: selectedRange == range ? .semibold : .medium))
                        .foregroundStyle(
                            selectedRange == range ? Color.white : SpendScopeTheme.dashboardMutedText
                        )
                        .frame(width: 54, height: 26)
                        .background {
                            if selectedRange == range {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(SpendScopeTheme.dashboardAccent)
                                    .shadow(color: SpendScopeTheme.dashboardAccent.opacity(0.24), radius: 5, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            SpendScopeTheme.dashboardControlBackground,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(SpendScopeTheme.dashboardBorder.opacity(0.72))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("趋势时间范围")
    }

    private func updateHoveredUsage(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else {
            hoveredUsageID = nil
            return
        }

        let frame = geometry[plotFrame]
        guard frame.contains(location) else {
            hoveredUsageID = nil
            return
        }

        let plotX = location.x - frame.minX
        hoveredUsageID = selectedUsage.compactMap { item -> (id: DailyUsage.ID, distance: CGFloat)? in
            guard let itemX = proxy.position(forX: item.day) else { return nil }
            return (item.id, abs(itemX - plotX))
        }
        .min { $0.distance < $1.distance }?
        .id
    }

    private func trendSummary(_ title: String, value: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SpendScopeTheme.dashboardMutedText)
            Text(TokenFormatter.compact(value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(SpendScopeTheme.dashboardAccent)
                .monospacedDigit()
        }
    }
}
