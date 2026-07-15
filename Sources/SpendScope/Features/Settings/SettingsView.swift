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
    private enum Layout {
        static let labelWidth: CGFloat = 205
        static let controlWidth: CGFloat = 248
        static let columnSpacing: CGFloat = 20
        static let rowHeight: CGFloat = 48
        static let planBadgeWidth: CGFloat = 148
    }

    let store: DashboardStore
    @AppStorage(AppPreferenceKeys.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(AppPreferenceKeys.quotaDisplay) private var quotaDisplayRaw = QuotaDisplayPreference.remaining.rawValue
    @AppStorage(AppPreferenceKeys.showsFiveHour) private var showsFiveHour = true
    @AppStorage(AppPreferenceKeys.showsWeekly) private var showsWeekly = true
    @AppStorage(AppPreferenceKeys.showsToday) private var showsToday = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("通用", systemImage: "gearshape.fill") }

            planSettings
                .tabItem { Label("套餐", systemImage: "shippingbox.fill") }

            dataSettings
                .tabItem { Label("数据", systemImage: "externaldrive.fill") }
        }
        .frame(width: 580, height: 660)
        .task { await store.start() }
    }

    private var generalSettings: some View {
        Form {
            Section("界面") {
                preferenceRow("外观", detail: "默认跟随 macOS 系统外观") {
                    Picker("", selection: $appearanceRaw) {
                        Text("自动").tag(AppearancePreference.system.rawValue)
                        Text("浅色").tag(AppearancePreference.light.rawValue)
                        Text("深色").tag(AppearancePreference.dark.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            Section("菜单栏") {
                preferenceRow("实时预览", detail: "菜单栏中将显示的统计摘要") {
                    Text(menuBarPreview)
                        .font(.callout.weight(.medium).monospacedDigit())
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }

                preferenceRow("额度口径", detail: "选择菜单栏百分比的统计方式") {
                    Picker("", selection: $quotaDisplayRaw) {
                        Text("已用量").tag(QuotaDisplayPreference.used.rawValue)
                        Text("剩余量").tag(QuotaDisplayPreference.remaining.rawValue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                preferenceRow("显示内容", detail: "可同时展示多个统计维度") {
                    HStack(spacing: 2) {
                        multiSelectSegment("5H", isOn: $showsFiveHour)
                        multiSelectSegment("7d", isOn: $showsWeekly)
                        multiSelectSegment("今日", isOn: $showsToday)
                    }
                    .padding(2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }
            }

            Section {
                preferenceRow("恢复默认", detail: "恢复外观与菜单栏显示设置") {
                    Button("恢复默认设置", systemImage: "arrow.counterclockwise") {
                        restoreDefaults()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
    }

    private var planSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsSection("Codex 套餐") {
                VStack(spacing: 0) {
                    ForEach(CodexPlanCatalog.plans) { plan in
                        planRow(plan)
                            .padding(.horizontal, 12)

                        if plan.id != CodexPlanCatalog.plans.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsCard()
            }

            settingsSection("其他计费方式") {
                VStack(spacing: 0) {
                    settingsRow {
                        settingLabel("API Key", detail: "独立按量计费，不属于 ChatGPT 订阅套餐")
                    } control: {
                        Text("按 Token 用量计费")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsCard()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dataSettings: some View {
        Form {
            Section("数据源") {
                healthRow("Codex CLI", health: store.sourceSummary?.cli)
                healthRow("Codex macOS", health: store.sourceSummary?.desktop)
                healthRow("线程索引", health: store.sourceSummary?.index)
                settingsRow {
                    Text("最近成功刷新")
                } control: {
                    Text(lastRefreshText)
                        .foregroundStyle(.secondary)
                }
            }

            Section("刷新") {
                settingsRow {
                    Text("自动刷新")
                } control: {
                    Text("每 60 秒")
                        .foregroundStyle(.secondary)
                }

                settingsRow {
                    settingLabel("手动刷新", detail: "立即重新读取本机 Codex 数据")
                } control: {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("立即刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isRefreshing)
                }
            }

            Section {
                Text("SpendScope 只读取本机 Codex 的安全统计字段，并将聚合数据保存在应用支持目录中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
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

            Spacer(minLength: 16)

            HStack(spacing: 6) {
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
            .frame(width: Layout.planBadgeWidth, alignment: .trailing)
        }
        .frame(minHeight: Layout.rowHeight)
    }

    private func isCurrent(_ plan: CodexPlan) -> Bool {
        CodexPlanCatalog.isCurrent(plan, currentPlanName: store.snapshot?.planName)
    }

    private var menuBarConfiguration: MenuBarLabelConfiguration {
        MenuBarLabelConfiguration(
            quotaDisplay: QuotaDisplayPreference(rawValue: quotaDisplayRaw) ?? .remaining,
            showsFiveHour: showsFiveHour,
            showsWeekly: showsWeekly,
            showsToday: showsToday
        )
    }

    private var menuBarPreview: String {
        store.menuBarLabel(configuration: menuBarConfiguration)
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func preferenceRow<Control: View>(
        _ title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        settingsRow {
            settingLabel(title, detail: detail)
        } control: {
            control()
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 4)

            content()
        }
    }

    private func multiSelectSegment(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 20)
                .foregroundStyle(isOn.wrappedValue ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(isOn.wrappedValue ? Color.accentColor : Color.clear)
        }
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private func settingsRow<Leading: View, Control: View>(
        @ViewBuilder label: () -> Leading,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: Layout.columnSpacing) {
            label()
                .frame(width: Layout.labelWidth, alignment: .leading)

            Spacer(minLength: 0)

            control()
                .frame(width: Layout.controlWidth, alignment: .trailing)
        }
        .frame(minHeight: Layout.rowHeight)
    }

    private func restoreDefaults() {
        appearanceRaw = AppearancePreference.system.rawValue
        quotaDisplayRaw = QuotaDisplayPreference.remaining.rawValue
        showsFiveHour = true
        showsWeekly = true
        showsToday = false
    }

    private func healthRow(_ title: String, health: SourceHealth?) -> some View {
        settingsRow {
            Text(title)
        } control: {
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

private extension View {
    func settingsCard() -> some View {
        background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }
}
