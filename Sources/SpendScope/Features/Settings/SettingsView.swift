import SwiftUI

struct SettingsView: View {
    let store: DashboardStore

    var body: some View {
        Form {
            Section("数据源") {
                healthRow("Codex CLI", health: store.sourceSummary?.cli)
                healthRow("Codex macOS", health: store.sourceSummary?.desktop)
                healthRow("线程索引", health: store.sourceSummary?.index)
                LabeledContent("最近成功刷新", value: lastRefreshText)
            }

            Section("刷新") {
                LabeledContent("自动刷新", value: "每 60 秒")
                Button("立即刷新", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .disabled(store.isRefreshing)
                if store.isRefreshing {
                    ProgressView("正在刷新…")
                        .controlSize(.small)
                }
            }

            Section {
                Text("SpendScope 只读取本机 Codex 的安全统计字段，并将聚合数据保存在应用支持目录中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
        .task { await store.start() }
    }

    private func healthRow(_ title: String, health: SourceHealth?) -> some View {
        LabeledContent(title) {
            Label(healthText(health), systemImage: healthSymbol(health))
                .foregroundStyle(healthColor(health))
        }
    }

    private var lastRefreshText: String {
        guard let date = store.sourceSummary?.lastSuccessfulRefresh else { return "尚未成功刷新" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private func healthText(_ health: SourceHealth?) -> String {
        switch health {
        case .connected: "已连接"
        case .missing: "未检测到"
        case .degraded: "部分不可用"
        case .unsupported: "格式不兼容"
        case nil: "正在检测"
        }
    }

    private func healthSymbol(_ health: SourceHealth?) -> String {
        switch health {
        case .connected: "checkmark.circle.fill"
        case .missing, nil: "minus.circle"
        case .degraded: "exclamationmark.triangle.fill"
        case .unsupported: "xmark.octagon.fill"
        }
    }

    private func healthColor(_ health: SourceHealth?) -> Color {
        switch health {
        case .connected: .green
        case .missing, nil: .secondary
        case .degraded: .orange
        case .unsupported: .red
        }
    }
}
