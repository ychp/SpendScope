import SwiftUI

struct CodexPlan: Identifiable, Sendable {
    let name: String
    let summary: String
    let symbol: String
    let isPaid: Bool

    var id: String { name }
}

enum CodexPlanCatalog {
    static let plans: [CodexPlan] = [
        .init(
            name: "Free",
            summary: "适合体验 Codex 和处理简短编码任务",
            symbol: "sparkles",
            isPaid: false
        ),
        .init(
            name: "Go",
            summary: "适合轻量、日常的编码任务",
            symbol: "figure.walk.motion",
            isPaid: true
        ),
        .init(
            name: "Plus",
            summary: "适合每周进行几次专注的编码工作",
            symbol: "plus.circle.fill",
            isPaid: true
        ),
        .init(
            name: "Pro 5x",
            summary: "标准使用额度为 Plus 的 5 倍",
            symbol: "bolt.fill",
            isPaid: true
        ),
        .init(
            name: "Pro 20x",
            summary: "最高用量档位，标准使用额度为 Plus 的 20 倍",
            symbol: "bolt.horizontal.circle.fill",
            isPaid: true
        ),
        .init(
            name: "Business",
            summary: "面向团队，包含工作区和基础管理能力",
            symbol: "person.2.fill",
            isPaid: true
        ),
        .init(
            name: "Enterprise / Edu",
            summary: "面向组织和教育机构，提供企业级控制能力",
            symbol: "building.2.fill",
            isPaid: true
        )
    ]

    static func isCurrent(_ plan: CodexPlan, currentPlanName: String?) -> Bool {
        plan.name.caseInsensitiveCompare(currentPlanName ?? "Free") == .orderedSame
    }
}

struct SettingsView: View {
    let store: DashboardStore

    var body: some View {
        TabView {
            planSettings
                .tabItem { Label("套餐", systemImage: "shippingbox.fill") }

            dataSettings
                .tabItem { Label("数据", systemImage: "externaldrive.fill") }
        }
        .frame(width: 580, height: 660)
        .task { await store.start() }
    }

    private var planSettings: some View {
        Form {
            Section {
                ForEach(CodexPlanCatalog.plans) { plan in
                    planRow(plan)
                }
            } header: {
                Text("Codex 套餐")
            }

            Section("其他计费方式") {
                LabeledContent {
                    Text("按 Token 用量计费")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("API Key", systemImage: "key.fill")
                }
                Text("API Key 是独立的按量计费方式，不属于 ChatGPT 订阅套餐。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
    }

    private var dataSettings: some View {
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
    }

    private func planRow(_ plan: CodexPlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: plan.symbol)
                .font(.title3)
                .foregroundStyle(isCurrent(plan) ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(plan.name)
                    .fontWeight(isCurrent(plan) ? .semibold : .regular)
                Text(plan.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if plan.isPaid {
                Text("付费")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            if isCurrent(plan) {
                Label("当前套餐", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }

    private func isCurrent(_ plan: CodexPlan) -> Bool {
        CodexPlanCatalog.isCurrent(plan, currentPlanName: store.snapshot?.planName)
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
