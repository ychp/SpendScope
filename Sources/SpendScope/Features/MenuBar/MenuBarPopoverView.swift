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
            Image(systemName: "chart.bar.fill")
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

            HStack(spacing: 20) {
                quotaColumn(
                    store.snapshot?.fiveHourQuota,
                    title: "5 小时",
                    color: SpendScopeTheme.accent
                )
                quotaColumn(
                    store.snapshot?.weeklyQuota,
                    title: "7 天",
                    color: SpendScopeTheme.accentBlue
                )
            }

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
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("设置", systemImage: "gearshape") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("退出", systemImage: "power") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.bordered)
    }

    private func quotaColumn(
        _ quota: QuotaSnapshot?,
        title: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(title)剩余").foregroundStyle(.secondary)
            Text(quota.map { "\($0.remainingPercent)%" } ?? "--")
                .font(.title.bold())
                .monospacedDigit()
            ProgressView(value: quota?.remaining ?? 0).tint(color)
            Text(quota?.resetText ?? "暂无额度数据")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
