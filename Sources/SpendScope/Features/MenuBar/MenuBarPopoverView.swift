import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(spacing: 16) {
            header
            usageCard
            footerActions
        }
        .padding(18)
        .frame(width: 420)
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
                Text(snapshot.updatedText).foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("刷新")
        }
    }

    private var usageCard: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Codex · \(snapshot.planName)", systemImage: "shippingbox.fill")
                    .font(.headline)
                Spacer()
                Text("可用")
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 20) {
                ForEach(snapshot.visibleQuotas) { quota in
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(quota.title)剩余").foregroundStyle(.secondary)
                        Text("\(quota.remainingPercent)%").font(.title.bold())
                        ProgressView(value: quota.remaining).tint(quotaColor(for: quota))
                        Text(quota.resetText).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            HStack {
                Text("今日 Token").font(.headline)
                Spacer()
                Text(TokenFormatter.compact(snapshot.todayTokens))
                    .font(.title2.bold())
                    .monospacedDigit()
            }

            breakdownRow("输入", snapshot.breakdown.input, SpendScopeTheme.accent)
            breakdownRow("缓存", snapshot.breakdown.cachedInput, SpendScopeTheme.accentBlue)
            breakdownRow("输出", snapshot.breakdown.output, SpendScopeTheme.output)
            breakdownRow("推理", snapshot.breakdown.reasoning, SpendScopeTheme.reasoning)
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

    private func breakdownRow(_ title: String, _ value: Int, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title)
            Spacer()
            Text(TokenFormatter.compact(value)).monospacedDigit()
        }
    }

    private func quotaColor(for quota: QuotaSnapshot) -> Color {
        quota.id == "7d" ? SpendScopeTheme.accentBlue : SpendScopeTheme.accent
    }
}
