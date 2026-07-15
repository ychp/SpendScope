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
        VStack(spacing: 16) {
            header
            usageCard
            footerActions
        }
        .padding(18)
        .frame(width: 420)
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
                Text(updatedText).foregroundStyle(.secondary)
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
        VStack(spacing: 14) {
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

            quotaSection

            Divider()

            HStack {
                Text("今日 Token").font(.headline)
                Spacer()
                Text(store.snapshot.map { TokenFormatter.compact($0.todayTokens) } ?? "--")
                    .font(.title2.bold())
                    .monospacedDigit()
            }

            breakdownRow("输入", store.snapshot?.breakdown.input, SpendScopeTheme.accent)
            breakdownRow("缓存", store.snapshot?.breakdown.cachedInput, SpendScopeTheme.accentBlue)
            breakdownRow("输出", store.snapshot?.breakdown.output, SpendScopeTheme.output)
            breakdownRow("推理", store.snapshot?.breakdown.reasoning, SpendScopeTheme.reasoning)
        }
        .dashboardCard()
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

    @ViewBuilder
    private var quotaSection: some View {
        let quotas = store.snapshot?.visibleQuotas ?? []

        if quotas.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("暂无可用额度数据")
                        .font(.headline)
                    Text("等待 Codex 返回额度信息")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        } else if quotas.count == 1, let quota = quotas.first {
            wideQuotaRow(quota, color: quotaColor(for: quota))
        } else {
            HStack(spacing: 20) {
                ForEach(quotas) { quota in
                    quotaColumn(quota, color: quotaColor(for: quota))
                }
            }
        }
    }

    private func wideQuotaRow(_ quota: QuotaSnapshot, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("\(quota.title)额度")
                    .font(.headline)

                Text("\(quota.remainingPercent)% 剩余")
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12), in: Capsule())

                Spacer(minLength: 8)

                Label("\(quota.resetText) 重置", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ProgressView(value: quota.remaining)
                .tint(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func quotaColumn(_ quota: QuotaSnapshot, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(quota.title)额度")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text("\(quota.remainingPercent)%")
                    .font(.title2.bold())
                    .monospacedDigit()
            }
            ProgressView(value: quota.remaining).tint(color)
            Label("\(quota.resetText) 重置", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quotaColor(for quota: QuotaSnapshot) -> Color {
        quota.id == "7d" ? SpendScopeTheme.accentBlue : SpendScopeTheme.accent
    }

    private func breakdownRow(_ title: String, _ value: Int?, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title)
            Spacer()
            Text(value.map(TokenFormatter.compact) ?? "--").monospacedDigit()
        }
    }

    private var updatedText: String {
        if let snapshot = store.snapshot { return snapshot.updatedText }
        return switch store.state {
        case .loading: "正在载入"
        case .empty: "未检测到 Codex 数据"
        case .failed(let message), .unsupported(let message): message
        case .loaded, .stale: "已刷新"
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
