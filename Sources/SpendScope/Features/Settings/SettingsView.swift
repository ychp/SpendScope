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
        static let rowHeight: CGFloat = 56
        static let cardHorizontalPadding: CGFloat = 16
        static let planBadgeWidth: CGFloat = 52
    }

    let store: DashboardStore
    let reminderController: UsageReminderController
    @AppStorage(AppPreferenceKeys.keepsDashboardOnTop) private var keepsDashboardOnTop = false
    @AppStorage(AppPreferenceKeys.automaticRefreshEnabled) private var automaticRefreshEnabled = true
    @AppStorage(AppPreferenceKeys.usageRemindersEnabled) private var usageRemindersEnabled = false
    @AppStorage(AppPreferenceKeys.remindsFiveHour) private var remindsFiveHour = true
    @AppStorage(AppPreferenceKeys.remindsWeekly) private var remindsWeekly = true
    @AppStorage(AppPreferenceKeys.remindsAtTwentyPercent) private var remindsAtTwentyPercent = true
    @AppStorage(AppPreferenceKeys.remindsAtTenPercent) private var remindsAtTenPercent = true
    @AppStorage(AppPreferenceKeys.remindsAtFivePercent) private var remindsAtFivePercent = true
    @AppStorage(AppPreferenceKeys.showsLivePreview) private var showsLivePreview = true
    @AppStorage(AppPreferenceKeys.showsResetCountdown) private var showsResetCountdown = true
    @AppStorage(AppPreferenceKeys.quotaDisplay) private var quotaDisplayRaw = QuotaDisplayPreference.remaining.rawValue
    @AppStorage(AppPreferenceKeys.showsFiveHour) private var showsFiveHour = true
    @AppStorage(AppPreferenceKeys.showsWeekly) private var showsWeekly = true
    @State private var showsRebuildConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dashboardSettings
                statusBarSettings
                usageReminderSettings
                dataAndRefreshSettings
                planAndBillingSettings
                privacyNotice
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.automatic)
        .frame(width: 600, height: 660)
        .background {
            SpendScopeVisualEffect(style: .window)
                .ignoresSafeArea()
        }
        .task {
            await store.start()
            await reminderController.refreshAuthorizationStatus()
        }
        .alert("清空并重新抓取所有数据？", isPresented: $showsRebuildConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空并重新抓取", role: .destructive) {
                Task { await store.rebuildFromLocalData() }
            }
        } message: {
            Text("这会清空 SpendScope 已抓取的用量、额度、会话和 Skills / Tools 统计，然后从本机 Codex 数据全量重新抓取。不会删除 Codex 原始数据。")
        }
    }

    private var dashboardSettings: some View {
        settingsSection("看板") {
            VStack(spacing: 0) {
                preferenceRow("置顶显示", detail: "让看板始终显示在其他普通窗口上方") {
                    Toggle("", isOn: $keepsDashboardOnTop)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .settingsCard()
        }
    }

    private var statusBarSettings: some View {
        settingsSection("状态栏") {
            VStack(spacing: 0) {
                preferenceRow("实时预览", detail: "在设置中显示状态栏当前效果") {
                    Toggle("", isOn: $showsLivePreview)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                VStack(spacing: 0) {
                    settingsDivider
                    preferenceRow("预览效果", detail: "与实际状态栏使用同一绘制样式") {
                        Image(nsImage: StatusItemRenderer().render(
                            statusItemPresentation,
                            appearance: previewAppearance
                        ))
                        .interpolation(.high)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityLabel("SpendScope 状态栏预览")
                        .accessibilityValue(statusItemPresentation.label)
                    }
                    settingsDivider

                    preferenceRow("额度口径", detail: "选择状态栏百分比的统计方式") {
                        segmentedGroup {
                            selectionSegment(
                                "已用量",
                                isSelected: quotaDisplayRaw == QuotaDisplayPreference.used.rawValue
                            ) {
                                quotaDisplayRaw = QuotaDisplayPreference.used.rawValue
                            }
                            selectionSegment(
                                "剩余量",
                                isSelected: quotaDisplayRaw == QuotaDisplayPreference.remaining.rawValue
                            ) {
                                quotaDisplayRaw = QuotaDisplayPreference.remaining.rawValue
                            }
                        }
                    }
                    settingsDivider

                    preferenceRow("显示内容", detail: "不可用额度会自动隐藏，至少保留一项") {
                        segmentedGroup {
                            multiSelectSegment("5H", isOn: fiveHourVisibilityBinding)
                            multiSelectSegment("7d", isOn: weeklyVisibilityBinding)
                        }
                    }
                    settingsDivider

                    preferenceRow("重置倒计时", detail: "控制状态栏及悬浮提示中的倒计时") {
                        Toggle("", isOn: $showsResetCountdown)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                .disabled(!showsLivePreview)
                .opacity(showsLivePreview ? 1 : 0.45)
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .settingsCard()
        }
    }

    private var usageReminderSettings: some View {
        settingsSection("用量提醒") {
            VStack(spacing: 0) {
                preferenceRow("用量提醒", detail: "额度较低时发送 macOS 系统通知") {
                    Toggle("", isOn: usageRemindersEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                VStack(spacing: 0) {
                    settingsDivider
                    preferenceRow("提醒额度", detail: "选择需要监控的额度，至少保留一项") {
                        segmentedGroup {
                            multiSelectSegment("5H", isOn: reminderFiveHourBinding)
                            multiSelectSegment("7d", isOn: reminderWeeklyBinding)
                        }
                    }
                    settingsDivider
                    preferenceRow("预警等级", detail: "剩余额度达到阈值时提醒") {
                        segmentedGroup {
                            multiSelectSegment("20%", isOn: reminderTwentyBinding)
                            multiSelectSegment("10%", isOn: reminderTenBinding)
                            multiSelectSegment("5%", isOn: reminderFiveBinding)
                        }
                    }
                    settingsDivider
                    preferenceRow("提醒规则", detail: "避免同一额度周期重复打扰") {
                        Text("每档每周期一次")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!usageRemindersEnabled)
                .opacity(usageRemindersEnabled ? 1 : 0.45)

                settingsDivider
                preferenceRow("通知权限", detail: notificationPermissionDetail) {
                    notificationPermissionControl
                }
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .settingsCard()
        }
    }

    @ViewBuilder
    private var notificationPermissionControl: some View {
        switch reminderController.authorizationStatus {
        case .notDetermined:
            Label("开启后请求", systemImage: "bell")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        case .authorized:
            Label("已允许", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
        case .denied:
            HStack(spacing: 8) {
                Label("未授权", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                Button("系统设置") {
                    reminderController.openNotificationSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var notificationPermissionDetail: String {
        switch reminderController.authorizationStatus {
        case .notDetermined: "首次开启提醒时申请系统权限"
        case .authorized: "系统通知可以正常发送"
        case .denied: "请在系统设置中允许 SpendScope 通知"
        }
    }

    private var dataAndRefreshSettings: some View {
        settingsSection("数据与刷新") {
            VStack(spacing: 0) {
                healthRow(
                    "Codex CLI",
                    detail: "命令行会话与用量数据",
                    health: store.sourceSummary?.cli
                )
                settingsDivider
                healthRow(
                    "Codex macOS",
                    detail: "桌面端会话与用量数据",
                    health: store.sourceSummary?.desktop
                )
                settingsDivider
                healthRow(
                    "线程索引",
                    detail: "本地线程状态与归档信息",
                    health: store.sourceSummary?.index
                )
                settingsDivider
                preferenceRow("最近成功刷新", detail: "最近一次成功读取本机数据的时间") {
                    Text(lastRefreshText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                settingsDivider
                preferenceRow(
                    "自动刷新",
                    detail: automaticRefreshEnabled
                        ? "在后台每 60 秒更新统计数据"
                        : "已关闭，仍可启动时读取或手动刷新"
                ) {
                    HStack(spacing: 10) {
                        Text(automaticRefreshEnabled ? "每 60 秒" : "已关闭")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: automaticRefreshBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                settingsDivider
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
                    .disabled(store.isRefreshing || store.isRebuildingData)
                }
                settingsDivider
                settingsRow {
                    settingLabel("重建本地数据", detail: "清空统计与检查点后全量重新抓取")
                } control: {
                    Button(role: .destructive) {
                        showsRebuildConfirmation = true
                    } label: {
                        if store.isRebuildingData {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在重新抓取")
                            }
                        } else {
                            Label("清空并重抓", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isRefreshing || store.isRebuildingData)
                }
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .settingsCard()
        }
    }

    private var planAndBillingSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("Codex 套餐") {
                VStack(spacing: 0) {
                    ForEach(CodexPlanCatalog.plans) { plan in
                        planRow(plan)
                            .padding(.horizontal, Layout.cardHorizontalPadding)
                            .background {
                                if isCurrent(plan) {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.08))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                }
                            }
                            .overlay {
                                if isCurrent(plan) {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                }
                            }

                        if plan.id != CodexPlanCatalog.plans.last?.id {
                            settingsDivider
                                .padding(.horizontal, Layout.cardHorizontalPadding)
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
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Layout.cardHorizontalPadding)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsCard()
            }
        }
    }

    private var automaticRefreshBinding: Binding<Bool> {
        Binding(
            get: { automaticRefreshEnabled },
            set: { isEnabled in
                automaticRefreshEnabled = isEnabled
                store.setAutomaticRefreshEnabled(isEnabled)
            }
        )
    }

    private var privacyNotice: some View {
        Label {
            Text("SpendScope 只读取本机 Codex 的安全统计字段，并将聚合数据保存在应用支持目录中。")
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func planRow(_ plan: CodexPlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: plan.symbol)
                .font(.title3)
                .foregroundStyle(isCurrent(plan) ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plan.name)
                        .fontWeight(isCurrent(plan) ? .semibold : .regular)

                    if isCurrent(plan) {
                        Label("当前套餐", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }

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
            showsLivePreview: showsLivePreview,
            quotaDisplay: QuotaDisplayPreference(rawValue: quotaDisplayRaw) ?? .remaining,
            showsFiveHour: showsFiveHour,
            showsWeekly: showsWeekly,
            showsResetCountdown: showsResetCountdown
        )
    }

    private var statusItemPresentation: StatusItemPresentation {
        StatusItemPresentation(
            snapshot: store.snapshot,
            configuration: menuBarConfiguration
        )
    }

    private var previewAppearance: NSAppearance {
        return NSAppearance(named: .aqua)!
    }

    private var fiveHourVisibilityBinding: Binding<Bool> {
        Binding(
            get: { showsFiveHour },
            set: { isVisible in
                guard isVisible || showsWeekly else { return }
                showsFiveHour = isVisible
            }
        )
    }

    private var weeklyVisibilityBinding: Binding<Bool> {
        Binding(
            get: { showsWeekly },
            set: { isVisible in
                guard isVisible || showsFiveHour else { return }
                showsWeekly = isVisible
            }
        )
    }

    private var usageRemindersEnabledBinding: Binding<Bool> {
        Binding(
            get: { usageRemindersEnabled },
            set: { isEnabled in
                usageRemindersEnabled = isEnabled
                reminderController.configurationDidChange(
                    requestAuthorizationIfNeeded: isEnabled
                )
            }
        )
    }

    private var reminderFiveHourBinding: Binding<Bool> {
        Binding(
            get: { remindsFiveHour },
            set: { isSelected in
                guard isSelected || remindsWeekly else { return }
                remindsFiveHour = isSelected
                reminderController.configurationDidChange()
            }
        )
    }

    private var reminderWeeklyBinding: Binding<Bool> {
        Binding(
            get: { remindsWeekly },
            set: { isSelected in
                guard isSelected || remindsFiveHour else { return }
                remindsWeekly = isSelected
                reminderController.configurationDidChange()
            }
        )
    }

    private var reminderTwentyBinding: Binding<Bool> {
        Binding(
            get: { remindsAtTwentyPercent },
            set: { isSelected in
                guard isSelected || remindsAtTenPercent || remindsAtFivePercent else { return }
                remindsAtTwentyPercent = isSelected
                reminderController.configurationDidChange()
            }
        )
    }

    private var reminderTenBinding: Binding<Bool> {
        Binding(
            get: { remindsAtTenPercent },
            set: { isSelected in
                guard isSelected || remindsAtTwentyPercent || remindsAtFivePercent else { return }
                remindsAtTenPercent = isSelected
                reminderController.configurationDidChange()
            }
        )
    }

    private var reminderFiveBinding: Binding<Bool> {
        Binding(
            get: { remindsAtFivePercent },
            set: { isSelected in
                guard isSelected || remindsAtTwentyPercent || remindsAtTenPercent else { return }
                remindsAtFivePercent = isSelected
                reminderController.configurationDidChange()
            }
        )
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

    private var settingsDivider: some View {
        Divider()
            .accessibilityHidden(true)
    }

    private func segmentedGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func selectionSegment(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 20)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func multiSelectSegment(_ title: String, isOn: Binding<Bool>) -> some View {
        selectionSegment(title, isSelected: isOn.wrappedValue) {
            isOn.wrappedValue.toggle()
        }
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

    private func healthRow(_ title: String, detail: String, health: SourceHealth?) -> some View {
        settingsRow {
            settingLabel(title, detail: detail)
        } control: {
            Label(healthText(health), systemImage: healthSymbol(health))
                .font(.callout.weight(.medium))
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
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return background {
            shape
                .fill(.thinMaterial)
                .overlay { shape.fill(Color.white.opacity(0.28)) }
        }
        .overlay {
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.62), Color(nsColor: .separatorColor).opacity(0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
        .shadow(color: Color.black.opacity(0.035), radius: 9, y: 3)
    }
}
