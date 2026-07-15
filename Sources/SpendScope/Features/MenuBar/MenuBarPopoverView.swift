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
    static func text(for state: DashboardLoadState) -> String {
        switch state {
        case .loading:
            "正在载入"
        case .loaded(let snapshot, _):
            snapshot.updatedText
        case .empty:
            "未检测到 Codex 数据"
        case .stale(let snapshot, _, _):
            "部分数据待更新 · \(snapshot.updatedText)"
        case .failed(let message), .unsupported(let message):
            message
        }
    }
}

enum MenuBarQuotaResetText {
    static func text(for quota: QuotaSnapshot, now: Date = Date()) -> String {
        quota.resetDescription(now: now) ?? "\(quota.resetText) 重置"
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
            usageCard
            footerActions
        }
        .padding(14)
        .frame(width: 390)
        .task { await store.start() }
    }

    private var header: some View {
        HStack {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .font(.title2)
                .foregroundStyle(.white)
                .padding(10)
                .background(SpendScopeTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text("SpendScope").font(.title2.bold())
                Text(MenuBarUpdateText.text(for: store.state))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help("刷新")
        }
    }

    private var usageCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Codex · \(store.snapshot?.planName ?? "未检测到")", systemImage: "shippingbox.fill")
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

            LazyVGrid(columns: tokenMetricColumns, spacing: 8) {
                ForEach(tokenMetrics) { metric in
                    tokenMetricCard(metric)
                }
            }
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
            Button("设置", systemImage: "gearshape") {
                if let onOpenSettings {
                    onOpenSettings()
                } else {
                    openSettings()
                }
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("退出", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.bordered)
    }

    private var quotaAndTodaySummary: some View {
        HStack(alignment: .top, spacing: 10) {
            quotaSection

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text("今日 Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(store.snapshot.map { TokenFormatter.compact($0.todayTokens) } ?? "--")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 84, alignment: .leading)
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.07))
        }
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

            Text(MenuBarQuotaResetText.text(for: quota))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
            MenuBarTokenMetric(id: "input", title: "未缓存输入", value: breakdown?.input, total: total, color: SpendScopeTheme.accent),
            MenuBarTokenMetric(id: "cached", title: "缓存", value: breakdown?.cachedInput, total: total, color: SpendScopeTheme.accentBlue),
            MenuBarTokenMetric(id: "output", title: "输出", value: breakdown?.output, total: total, color: SpendScopeTheme.output),
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

                Spacer(minLength: 4)

                Text(metric.shareText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(metric.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(metric.color.opacity(0.1), in: Capsule())
            }

            HStack(alignment: .lastTextBaseline) {
                Text(metric.valueText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Spacer(minLength: 8)

                Text("占今日")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

        }
        .padding(9)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.primary.opacity(0.06))
        }
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
