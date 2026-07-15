import AppKit
import SwiftUI

enum MenuBarAvailabilityText {
    static func text(for state: DashboardLoadState) -> String {
        switch state {
        case .loaded: "可用"
        case .stale: "数据待更新"
        case .loading: "载入中"
        case .empty: "暂无数据"
        case .failed, .unsupported: "不可用"
        }
    }
}

enum MenuBarUpdateText {
    static func text(
        for state: DashboardLoadState,
        calendar: Calendar = .current
    ) -> String {
        switch state {
        case .loading:
            "正在载入"
        case .loaded(let snapshot, let summary):
            snapshotText(snapshot, summary: summary, calendar: calendar)
        case .empty:
            "未检测到 Codex 数据"
        case .stale(let snapshot, let summary, _):
            "部分数据待更新 · \(snapshotText(snapshot, summary: summary, calendar: calendar))"
        case .failed(let message), .unsupported(let message):
            message
        }
    }

    private static func snapshotText(
        _ snapshot: DashboardSnapshot,
        summary: SourceSummary,
        calendar: Calendar
    ) -> String {
        let statusText = snapshot.updatedText == "刚刚刷新" ? "刚刚更新" : snapshot.updatedText
        guard let refreshedAt = summary.lastSuccessfulRefresh else { return statusText }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return "\(statusText) · \(formatter.string(from: refreshedAt))"
    }
}

enum MenuBarQuotaResetText {
    static func text(for quota: QuotaSnapshot, now: Date = Date()) -> String {
        quota.resetDescription(now: now) ?? "\(quota.resetText) 重置"
    }
}

enum MenuBarQuotaTimingText {
    static func text(for quota: QuotaSnapshot, now: Date = Date()) -> String {
        let resetText = MenuBarQuotaResetText.text(for: quota, now: now)
        guard let observationText = quota.observationDescription(now: now) else {
            return resetText
        }
        return "\(resetText) · \(observationText)"
    }
}

struct MenuBarUnavailableContent: Equatable {
    let title: String
    let description: String
    let systemImage: String
    let showsRefresh: Bool

    static func content(for state: DashboardLoadState) -> MenuBarUnavailableContent? {
        switch state {
        case .loading:
            MenuBarUnavailableContent(
                title: "正在载入 Codex 数据",
                description: "SpendScope 正在读取本地统计。",
                systemImage: "chart.bar.doc.horizontal",
                showsRefresh: false
            )
        case .empty:
            MenuBarUnavailableContent(
                title: "未检测到 Codex 数据",
                description: "使用 Codex 后重新刷新即可查看 Token 用量。",
                systemImage: "tray",
                showsRefresh: true
            )
        case .failed(let message):
            MenuBarUnavailableContent(
                title: "暂时无法读取数据",
                description: message,
                systemImage: "exclamationmark.triangle",
                showsRefresh: true
            )
        case .unsupported(let message):
            MenuBarUnavailableContent(
                title: "数据格式暂不兼容",
                description: message,
                systemImage: "doc.badge.ellipsis",
                showsRefresh: true
            )
        case .loaded, .stale:
            nil
        }
    }
}

enum MenuBarSummaryLayout: Equatable {
    case sideBySide
    case stacked

    static func layout(forQuotaCount count: Int) -> MenuBarSummaryLayout {
        count > 1 ? .stacked : .sideBySide
    }
}

struct MenuBarPopoverView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    let store: DashboardStore
    private let onOpenDashboard: (() -> Void)?
    private let onOpenSettings: (() -> Void)?

    init(
        store: DashboardStore,
        onOpenDashboard: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.store = store
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            popoverContent
            footerActions
        }
        .padding(14)
        .frame(width: 390)
        .task { await store.start() }
    }

    @ViewBuilder
    private var popoverContent: some View {
        if let content = MenuBarUnavailableContent.content(for: store.state) {
            unavailableCard(content)
        } else {
            usageCard
        }
    }

    private func unavailableCard(_ content: MenuBarUnavailableContent) -> some View {
        VStack(spacing: 9) {
            Image(systemName: content.systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(unavailableIconColor)

            Text(content.title)
                .font(.headline)

            Text(content.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if content.showsRefresh {
                Button("重新刷新", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.bordered)
                .disabled(store.isRefreshing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 136)
        .dashboardCard(padding: 14)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 21.5, height: 21.5)
                .foregroundStyle(.white)
                .padding(6.5)
                .background(
                    LinearGradient(
                        colors: [SpendScopeTheme.popoverSecondary, SpendScopeTheme.popoverPrimary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("SpendScope")
                    .font(.system(size: 14.5, weight: .bold))
                Text(MenuBarUpdateText.text(for: store.state))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.055))

                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(SpendScopeTheme.accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .accessibilityLabel(store.isRefreshing ? "正在刷新" : "刷新")
            .help(store.isRefreshing ? "正在刷新" : "刷新")
        }
    }

    private var usageCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image("CodexIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    Text("Codex · \(store.snapshot?.planName ?? "未检测到")")
                }
                .font(.headline)
                Spacer()
                Text(availabilityText)
                    .foregroundStyle(availabilityColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(availabilityColor.opacity(0.12), in: Capsule())
            }

            quotaAndTodaySummary

            tokenCompositionBar

            LazyVGrid(columns: tokenMetricColumns, spacing: 0) {
                ForEach(Array(tokenMetrics.enumerated()), id: \.element.id) { index, metric in
                    tokenMetricCard(metric)
                        .overlay(alignment: .trailing) {
                            if index.isMultiple(of: 2) {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.07))
                                    .frame(width: 1)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if index < 2 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.07))
                                    .frame(height: 1)
                            }
                        }
                }
            }
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .dashboardCard(padding: 14)
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            Button("打开看板", systemImage: "square.grid.2x2") {
                if let onOpenDashboard {
                    onOpenDashboard()
                } else {
                    openWindow(id: "dashboard")
                }
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)

            Button("设置", systemImage: "gearshape") {
                if let onOpenSettings {
                    onOpenSettings()
                } else {
                    openSettings()
                }
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Divider()
                .frame(height: 18)

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("退出 SpendScope")
        }
    }

    private var quotaAndTodaySummary: some View {
        let quotaCount = store.snapshot?.visibleQuotas.count ?? 0

        return Group {
            switch MenuBarSummaryLayout.layout(forQuotaCount: quotaCount) {
            case .sideBySide:
                HStack(alignment: .top, spacing: 10) {
                    quotaSection

                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: 58)

                    compactTodaySummary
                }
            case .stacked:
                VStack(spacing: 9) {
                    quotaSection

                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)

                    wideTodaySummary
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private var compactTodaySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日 Token")
                .font(.caption)
                .foregroundStyle(.secondary)

            todayTokenValue
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 84, height: 58, alignment: .top)
    }

    private var wideTodaySummary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("今日 Token")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            todayTokenValue
        }
    }

    private var todayTokenValue: some View {
        Text(store.snapshot.map { TokenFormatter.compact($0.todayTokens) } ?? "--")
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private var quotaSection: some View {
        let quotas = store.snapshot?.visibleQuotas ?? []

        if quotas.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("暂无可用额度数据")
                        .font(.subheadline.weight(.semibold))
                    Text("等待 Codex 返回额度信息")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                ForEach(quotas) { quota in
                    quotaColumn(quota, color: quotaColor(for: quota))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quotaColumn(_ quota: QuotaSnapshot, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(quota.title)剩余")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text("\(quota.remainingPercent)%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            ProgressView(value: quota.remaining)
                .tint(color)
                .controlSize(.mini)

            Text(MenuBarQuotaTimingText.text(for: quota))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("额度信息来自最近一次 Codex 本地观测")
    }

    private func quotaColor(for quota: QuotaSnapshot) -> Color {
        quota.id == "7d" ? SpendScopeTheme.accentBlue : SpendScopeTheme.accent
    }

    private var tokenMetricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }

    private var tokenCompositionBar: some View {
        let metrics = tokenMetrics
        let hasUsage = metrics.contains { $0.value != nil }

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("今日构成")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(hasUsage ? "按今日总量" : "暂无数据")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(metrics) { metric in
                        Rectangle()
                            .fill(metric.color)
                            .frame(width: geometry.size.width * metric.share)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日 Token 构成")
        .accessibilityValue(hasUsage ? metrics.map(\.accessibilityText).joined(separator: "，") : "暂无数据")
    }

    private var tokenMetrics: [MenuBarTokenMetric] {
        let breakdown = store.snapshot?.breakdown
        let total = store.snapshot?.todayTokens ?? 0
        return [
            MenuBarTokenMetric(id: "input", title: "输入（未缓存）", value: breakdown?.input, total: total, color: SpendScopeTheme.accent),
            MenuBarTokenMetric(id: "cached", title: "缓存输入", value: breakdown?.cachedInput, total: total, color: SpendScopeTheme.accentBlue),
            MenuBarTokenMetric(id: "output", title: "可见输出", value: breakdown?.output, total: total, color: SpendScopeTheme.output),
            MenuBarTokenMetric(id: "reasoning", title: "推理", value: breakdown?.reasoning, total: total, color: SpendScopeTheme.reasoning)
        ]
    }

    private func tokenMetricCard(_ metric: MenuBarTokenMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(metric.color)
                    .frame(width: 7, height: 7)

                Text(metric.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .lastTextBaseline) {
                Text(metric.valueText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Spacer(minLength: 8)

                HStack(spacing: 3) {
                    Text("占今日")
                        .foregroundStyle(.tertiary)
                    Text(metric.shareText)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(metric.color)
                }
                .font(.caption2)
            }

        }
        .padding(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.accessibilityText)
    }

    private var availabilityText: String {
        MenuBarAvailabilityText.text(for: store.state)
    }

    private var availabilityColor: Color {
        switch store.state {
        case .loaded: .green
        case .stale: .orange
        case .loading, .empty: .secondary
        case .failed, .unsupported: .red
        }
    }

    private var unavailableIconColor: Color {
        switch store.state {
        case .failed, .unsupported:
            .red
        case .stale:
            .orange
        case .loading, .empty, .loaded:
            SpendScopeTheme.popoverPrimary
        }
    }
}

private struct MenuBarTokenMetric: Identifiable {
    let id: String
    let title: String
    let value: Int?
    let total: Int
    let color: Color

    var share: Double {
        guard let value, total > 0 else { return 0 }
        return min(max(Double(value) / Double(total), 0), 1)
    }

    var valueText: String {
        value.map(TokenFormatter.compact) ?? "--"
    }

    var shareText: String {
        value == nil ? "--" : TokenFormatter.percentage(share)
    }

    var accessibilityText: String {
        "\(title) \(valueText)，占今日 \(shareText)"
    }
}
