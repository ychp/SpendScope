# SpendScope 原生 macOS 工程初始化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 初始化一个可编译、可测试、可作为 `.app` 启动的原生 SwiftUI macOS 应用，包含菜单栏入口、详细看板窗口、设置窗口和静态原型数据。

**架构：** 使用标准 Xcode macOS App 工程管理无第三方依赖的 Swift 6 源码，并以 `MenuBarExtra`、`Window`、`Settings` 和 Swift Charts 构建原生界面。应用状态先由不可变的 `DashboardSnapshot.preview` 提供，后续 Codex 数据采集模块通过替换该数据源接入。项目脚本使用固定 DerivedData 路径构建并启动 Xcode 直接产出的 `.app` Bundle。

**技术栈：** Xcode 26.6、Swift 6、SwiftUI、AppKit、Charts、XCTest、macOS 14+

## 全局约束

- 应用名称为 `SpendScope`，Bundle ID 为 `com.ychp.SpendScope`。
- 最低系统版本为 macOS 14.0。
- 工程不引入第三方依赖。
- 工程入口为 `SpendScope.xcodeproj`，共享 Scheme 名称为 `SpendScope`。
- 所有界面文案使用简体中文；产品名、Codex、模型名和技术标识保留英文。
- 初始化阶段只使用静态原型数据，不读取真实 Codex 文件。
- 菜单栏与详细看板必须是同一个原生应用进程中的两个入口。
- 命令行构建默认使用 `/private/tmp/SpendScope-DerivedData`，避免 `Documents` 的 File Provider 扩展属性破坏代码签名；可通过 `SPENDSCOPE_DERIVED_DATA` 覆盖。

---

## 文件结构

```text
SpendScope.xcodeproj/project.pbxproj       Xcode 工程、App 与测试目标声明
SpendScope.xcodeproj/xcshareddata/xcschemes/SpendScope.xcscheme 共享 Scheme
Sources/SpendScope/App/SpendScopeApp.swift 应用入口和 Scene 组合
Sources/SpendScope/App/AppDelegate.swift   macOS 激活策略
Sources/SpendScope/Models/DashboardSnapshot.swift 静态看板领域模型
Sources/SpendScope/Support/TokenFormatter.swift   Token 紧凑格式化
Sources/SpendScope/Support/DesignSystem.swift     颜色、间距和卡片样式
Sources/SpendScope/Features/MenuBar/MenuBarPopoverView.swift 菜单栏弹窗
Sources/SpendScope/Features/Dashboard/DashboardView.swift     详细看板
Sources/SpendScope/Features/Settings/SettingsView.swift       设置窗口
Tests/SpendScopeTests/TokenFormatterTests.swift                格式化测试
script/build_and_run.sh                    Xcode 构建和启动入口
.codex/environments/environment.toml       Codex Run 动作
.gitignore                                 Xcode 与构建产物忽略规则
README.md                                  开发和运行说明
```

### Task 1：建立可测试的 Xcode 原生应用工程

**文件：**

- 创建：`SpendScope.xcodeproj/project.pbxproj`
- 创建：`SpendScope.xcodeproj/xcshareddata/xcschemes/SpendScope.xcscheme`
- 创建：`Sources/SpendScope/App/SpendScopeApp.swift`（最小测试宿主，Task 2 扩展）
- 创建：`Sources/SpendScope/Models/DashboardSnapshot.swift`
- 创建：`Sources/SpendScope/Support/TokenFormatter.swift`
- 创建：`Tests/SpendScopeTests/TokenFormatterTests.swift`
- 创建：`.gitignore`

**接口：**

- 产出：`TokenFormatter.compact(_ value: Int) -> String`
- 产出：`DashboardSnapshot.preview`
- 产出：`QuotaSnapshot`, `TokenBreakdown`, `ModelUsage`, `DailyUsage`

- [ ] **Step 1：编写 Token 格式化失败测试**

```swift
import XCTest
@testable import SpendScope

final class TokenFormatterTests: XCTestCase {
    func testFormatsCompactValues() {
        XCTAssertEqual(TokenFormatter.compact(999), "999")
        XCTAssertEqual(TokenFormatter.compact(1_500), "1.5K")
        XCTAssertEqual(TokenFormatter.compact(17_000_000), "17.0M")
        XCTAssertEqual(TokenFormatter.compact(1_061_100_000), "1.1B")
    }
}
```

- [ ] **Step 2：创建 Xcode App、单元测试目标与共享 Scheme，并验证测试失败**

`SpendScope.xcodeproj` 必须包含以下确定配置：

- App 目标与 Product 名称：`SpendScope`；
- 测试目标：`SpendScopeTests`，依赖并加载 `SpendScope.app`；
- Bundle ID：`com.ychp.SpendScope`；
- macOS Deployment Target：`14.0`；
- Swift Language Version：`6.0`；
- 自动生成 Info.plist，并设置 `LSUIElement = YES`；
- 本地调试使用 ad-hoc 签名，不要求 Development Team；
- 共享 Scheme 同时包含 Build、Run 和 Test 动作。

同时创建可供单元测试加载的最小 App Host：

```swift
import SwiftUI

@main
struct SpendScopeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SpendScope")
        }
    }
}
```

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -derivedDataPath /private/tmp/SpendScope-DerivedData test
```

预期：失败，提示找不到 `TokenFormatter`。

- [ ] **Step 3：实现格式化器和静态领域模型**

创建 `Sources/SpendScope/Support/TokenFormatter.swift`：

```swift
import Foundation

enum TokenFormatter {
    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...:
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return String(value)
        }
    }
}
```

创建 `Sources/SpendScope/Models/DashboardSnapshot.swift`：

```swift
import Foundation

struct DashboardSnapshot: Sendable {
    let planName: String
    let updatedText: String
    let todayTokens: Int
    let sevenDayTokens: Int
    let totalTokens: Int
    let quotas: [QuotaSnapshot]
    let breakdown: TokenBreakdown
    let models: [ModelUsage]
    let dailyUsage: [DailyUsage]

    static let preview = DashboardSnapshot(
        planName: "Pro",
        updatedText: "刚刚刷新",
        todayTokens: 17_000_000,
        sevenDayTokens: 84_200_000,
        totalTokens: 326_800_000,
        quotas: [
            QuotaSnapshot(id: "5h", title: "5 小时", remaining: 0.85, resetText: "02:52 重置"),
            QuotaSnapshot(id: "7d", title: "7 天", remaining: 0.84, resetText: "周一 10:45 重置")
        ],
        breakdown: TokenBreakdown(
            input: 8_200_000,
            cachedInput: 7_900_000,
            output: 700_000,
            reasoning: 200_000
        ),
        models: [
            ModelUsage(id: "gpt-5.5", name: "gpt-5.5", share: 0.68),
            ModelUsage(id: "gpt-5.4", name: "gpt-5.4", share: 0.32)
        ],
        dailyUsage: [
            DailyUsage(id: "5/10", day: "5/10", total: 9_800_000),
            DailyUsage(id: "5/11", day: "5/11", total: 13_100_000),
            DailyUsage(id: "5/12", day: "5/12", total: 15_000_000),
            DailyUsage(id: "5/13", day: "5/13", total: 15_700_000),
            DailyUsage(id: "5/14", day: "5/14", total: 16_300_000),
            DailyUsage(id: "5/15", day: "5/15", total: 12_900_000),
            DailyUsage(id: "5/16", day: "5/16", total: 12_100_000)
        ]
    )
}

struct QuotaSnapshot: Identifiable, Sendable {
    let id: String
    let title: String
    let remaining: Double
    let resetText: String

    var remainingPercent: Int { Int((remaining * 100).rounded()) }
}

struct TokenBreakdown: Sendable {
    let input: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int

    var total: Int { input + cachedInput + output + reasoning }
}

struct ModelUsage: Identifiable, Sendable {
    let id: String
    let name: String
    let share: Double
}

struct DailyUsage: Identifiable, Sendable {
    let id: String
    let day: String
    let total: Int
}
```

创建 `.gitignore`：

```gitignore
.DS_Store
.build/
DerivedData/
xcuserdata/
*.xcuserstate
```

- [ ] **Step 4：运行测试并确认通过**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -derivedDataPath /private/tmp/SpendScope-DerivedData test
```

预期：4 个断言全部通过。

- [ ] **Step 5：提交领域模型骨架**

```bash
git add SpendScope.xcodeproj Sources/SpendScope/Models Sources/SpendScope/Support/TokenFormatter.swift Tests .gitignore
git commit -m "feat: bootstrap SpendScope domain model"
```

### Task 2：建立菜单栏、详细看板和设置窗口

**文件：**

- 创建：`Sources/SpendScope/App/AppDelegate.swift`
- 修改：`Sources/SpendScope/App/SpendScopeApp.swift`
- 创建：`Sources/SpendScope/Support/DesignSystem.swift`
- 创建：`Sources/SpendScope/Features/MenuBar/MenuBarPopoverView.swift`
- 创建：`Sources/SpendScope/Features/Dashboard/DashboardView.swift`
- 创建：`Sources/SpendScope/Features/Settings/SettingsView.swift`

**接口：**

- 消费：`DashboardSnapshot.preview`
- 消费：`TokenFormatter.compact(_:)`
- 产出：`SpendScopeApp: App`
- 产出：`MenuBarPopoverView(snapshot:)`
- 产出：`DashboardView(snapshot:)`
- 产出：`SettingsView()`

- [ ] **Step 1：实现应用入口和激活策略**

`SpendScopeApp` 使用 `@NSApplicationDelegateAdaptor`，创建：

- `MenuBarExtra`，标签为 `5h 85% · 7d 84%`；
- ID 为 `dashboard` 的 `Window`；
- 原生 `Settings` Scene。

`AppDelegate` 在启动时设置 `.accessory` 激活策略；打开看板时调用 `NSApp.activate(ignoringOtherApps: true)`。

创建 `Sources/SpendScope/App/AppDelegate.swift`：

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

创建 `Sources/SpendScope/App/SpendScopeApp.swift`：

```swift
import SwiftUI

@main
struct SpendScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let snapshot = DashboardSnapshot.preview

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(snapshot: snapshot)
        } label: {
            Label(
                "5h \(snapshot.quotas[0].remainingPercent)% · 7d \(snapshot.quotas[1].remainingPercent)%",
                systemImage: "chart.bar.fill"
            )
        }
        .menuBarExtraStyle(.window)

        Window("SpendScope", id: "dashboard") {
            DashboardView(snapshot: snapshot)
        }
        .defaultSize(width: 1080, height: 760)

        Settings {
            SettingsView()
        }
    }
}
```

- [ ] **Step 2：实现统一视觉基础**

`DesignSystem.swift` 定义紫色主色、四类 Token 颜色、卡片背景和 `DashboardCard` 修饰器，供菜单栏和看板复用。

```swift
import SwiftUI

enum SpendScopeTheme {
    static let accent = Color(red: 0.42, green: 0.24, blue: 0.96)
    static let accentBlue = Color(red: 0.18, green: 0.52, blue: 0.96)
    static let output = Color.orange
    static let reasoning = Color.cyan
    static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.82)
}

struct DashboardCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(SpendScopeTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08))
            }
    }
}

extension View {
    func dashboardCard() -> some View {
        modifier(DashboardCard())
    }
}
```

- [ ] **Step 3：实现菜单栏弹窗**

弹窗固定宽度约 420 点，包含：

- SpendScope、刷新状态和刷新按钮；
- Codex · Pro 状态卡；
- 5 小时与 7 天额度进度；
- 今日 Token 总量及输入、缓存、输出、推理明细；
- 打开看板、设置和退出三个操作。

创建 `Sources/SpendScope/Features/MenuBar/MenuBarPopoverView.swift`：

```swift
import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    let snapshot: DashboardSnapshot

    var body: some View {
        VStack(spacing: 16) {
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
                Button(action: {}) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }

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
                    ForEach(snapshot.quotas) { quota in
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(quota.title)剩余").foregroundStyle(.secondary)
                            Text("\(quota.remainingPercent)%").font(.title.bold())
                            ProgressView(value: quota.remaining).tint(SpendScopeTheme.accent)
                            Text(quota.resetText).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider()

                HStack {
                    Text("今日 Token").font(.headline)
                    Spacer()
                    Text(TokenFormatter.compact(snapshot.todayTokens)).font(.title2.bold())
                }

                breakdownRow("输入", snapshot.breakdown.input, SpendScopeTheme.accent)
                breakdownRow("缓存", snapshot.breakdown.cachedInput, SpendScopeTheme.accentBlue)
                breakdownRow("输出", snapshot.breakdown.output, SpendScopeTheme.output)
                breakdownRow("推理", snapshot.breakdown.reasoning, SpendScopeTheme.reasoning)
            }
            .dashboardCard()

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
        .padding(18)
        .frame(width: 420)
    }

    private func breakdownRow(_ title: String, _ value: Int, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title)
            Spacer()
            Text(TokenFormatter.compact(value)).monospacedDigit()
        }
    }
}
```

- [ ] **Step 4：实现详细看板**

看板固定最小尺寸约 1040 × 700 点，包含：

- 今日、近 7 天、累计三张摘要卡；
- 两个额度环形进度；
- 七日 Token 趋势折线图；
- 模型分布进度条；
- Token 构成及时间范围分段选择器。

创建 `Sources/SpendScope/Features/Dashboard/DashboardView.swift`：

```swift
import Charts
import SwiftUI

struct DashboardView: View {
    let snapshot: DashboardSnapshot
    @State private var selectedRange = "7 天"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SpendScope").font(.largeTitle.bold())
                        Text("Codex · \(snapshot.planName)  ·  \(snapshot.updatedText)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("时间范围", selection: $selectedRange) {
                        ForEach(["今日", "7 天", "30 天", "全部"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }

                HStack(spacing: 14) {
                    metricCard("今日", snapshot.todayTokens, "waveform.path.ecg")
                    metricCard("近 7 天", snapshot.sevenDayTokens, "calendar")
                    metricCard("累计", snapshot.totalTokens, "square.stack.3d.up.fill")
                }

                HStack(alignment: .top, spacing: 14) {
                    quotaCard.frame(maxWidth: .infinity)
                    modelCard.frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 14) {
                    trendCard.frame(maxWidth: .infinity)
                    compositionCard.frame(width: 360)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 1040, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func metricCard(_ title: String, _ value: Int, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(SpendScopeTheme.accent).font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).foregroundStyle(.secondary)
                Text(TokenFormatter.compact(value)).font(.system(size: 30, weight: .bold)).monospacedDigit()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .dashboardCard()
    }

    private var quotaCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("额度状态").font(.headline)
            HStack(spacing: 36) {
                ForEach(snapshot.quotas) { quota in
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 9)
                            Circle()
                                .trim(from: 0, to: quota.remaining)
                                .stroke(SpendScopeTheme.accent.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack {
                                Text(quota.title).font(.caption)
                                Text("\(quota.remainingPercent)%").font(.title.bold())
                                Text("剩余").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 118, height: 118)
                        Text(quota.resetText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .dashboardCard()
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("模型分布").font(.headline)
            ForEach(snapshot.models) { model in
                VStack(spacing: 8) {
                    HStack {
                        Text(model.name)
                        Spacer()
                        Text("\(Int(model.share * 100))%").monospacedDigit()
                    }
                    ProgressView(value: model.share).tint(SpendScopeTheme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .dashboardCard()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token 趋势").font(.headline)
            Chart(snapshot.dailyUsage) { item in
                AreaMark(x: .value("日期", item.day), y: .value("Token", item.total))
                    .foregroundStyle(SpendScopeTheme.accent.opacity(0.12))
                LineMark(x: .value("日期", item.day), y: .value("Token", item.total))
                    .foregroundStyle(SpendScopeTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                PointMark(x: .value("日期", item.day), y: .value("Token", item.total))
                    .foregroundStyle(SpendScopeTheme.accent)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) { Text(TokenFormatter.compact(tokens)) }
                    }
                }
            }
            .frame(height: 260)
        }
        .dashboardCard()
    }

    private var compositionCard: some View {
        let values = [
            ("输入", snapshot.breakdown.input, SpendScopeTheme.accent),
            ("缓存输入", snapshot.breakdown.cachedInput, SpendScopeTheme.accentBlue),
            ("输出", snapshot.breakdown.output, SpendScopeTheme.output),
            ("推理", snapshot.breakdown.reasoning, SpendScopeTheme.reasoning)
        ]

        return VStack(alignment: .leading, spacing: 18) {
            Text("Token 构成").font(.headline)
            ForEach(values, id: \.0) { title, value, color in
                VStack(spacing: 7) {
                    HStack {
                        Circle().fill(color).frame(width: 9, height: 9)
                        Text(title)
                        Spacer()
                        Text(TokenFormatter.compact(value)).monospacedDigit()
                    }
                    ProgressView(value: Double(value), total: Double(snapshot.breakdown.total)).tint(color)
                }
            }
            Spacer(minLength: 0)
        }
        .dashboardCard()
    }
}
```

- [ ] **Step 5：实现设置窗口**

设置页包含静态的 Codex CLI/桌面来源状态、60 秒刷新选项、开机启动与两档通知开关，并明确标注“原型数据，尚未读取真实 Codex 数据”。

创建 `Sources/SpendScope/Features/Settings/SettingsView.swift`：

```swift
import SwiftUI

struct SettingsView: View {
    @State private var refreshInterval = 60
    @State private var launchAtLogin = false
    @State private var notifyAtTwenty = true
    @State private var notifyAtFive = true

    var body: some View {
        Form {
            Section("数据源") {
                LabeledContent("Codex CLI", value: "待接入")
                LabeledContent("Codex macOS", value: "待接入")
                Text("当前展示原型数据，尚未读取真实 Codex 数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("刷新") {
                Picker("自动刷新", selection: $refreshInterval) {
                    Text("30 秒").tag(30)
                    Text("60 秒").tag(60)
                    Text("5 分钟").tag(300)
                }
                Toggle("开机启动", isOn: $launchAtLogin)
            }
            Section("额度通知") {
                Toggle("剩余 20% 时通知", isOn: $notifyAtTwenty)
                Toggle("剩余 5% 时通知", isOn: $notifyAtFive)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
    }
}
```

- [ ] **Step 6：编译 UI 骨架**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -derivedDataPath /private/tmp/SpendScope-DerivedData build
```

预期：`** BUILD SUCCEEDED **`，无 Swift 并发或平台可用性错误。

- [ ] **Step 7：提交原生界面骨架**

```bash
git add Sources/SpendScope/App Sources/SpendScope/Features Sources/SpendScope/Support/DesignSystem.swift
git commit -m "feat: add native macOS app shell"
```

### Task 3：建立统一构建运行入口和开发文档

**文件：**

- 创建：`script/build_and_run.sh`
- 创建：`.codex/environments/environment.toml`
- 创建：`README.md`

**接口：**

- 消费：Xcode Scheme `SpendScope`
- 产出：`/private/tmp/SpendScope-DerivedData/Build/Products/Debug/SpendScope.app`
- 产出：`./script/build_and_run.sh [run|--debug|--logs|--telemetry|--verify]`

- [ ] **Step 1：创建构建运行脚本**

脚本必须：

1. 停止已运行的 `SpendScope` 进程；
2. 使用 `/Applications/Xcode.app` 和共享 Scheme 执行 `xcodebuild`；
3. 将 DerivedData 默认放在 `/private/tmp/SpendScope-DerivedData`，并允许环境变量覆盖；
4. 直接启动 Xcode 产出的 `SpendScope.app`；
5. 支持启动、LLDB、日志、Telemetry 和进程验证模式。

创建 `script/build_and_run.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SpendScope"
BUNDLE_ID="com.ychp.SpendScope"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/SpendScope.xcodeproj"
SCHEME="SpendScope"
DERIVED_DATA="${SPENDSCOPE_DERIVED_DATA:-/private/tmp/SpendScope-DerivedData}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 2：赋予脚本执行权限并配置 Codex Run 动作**

运行：`chmod +x script/build_and_run.sh`

`.codex/environments/environment.toml` 的 `Run` 动作固定执行：

```toml
# THIS IS AUTOGENERATED. DO NOT EDIT MANUALLY
version = 1
name = "SpendScope"

[setup]
script = ""

[[actions]]
name = "Run"
icon = "run"
command = "./script/build_and_run.sh"
```

- [ ] **Step 3：补充 README**

README 说明项目定位、当前原型范围、目录结构、Xcode 版本、命令行测试与构建、运行脚本，以及首次使用前必须完成 Xcode License 和组件初始化。

创建 `README.md`：

````markdown
# SpendScope

SpendScope 是一款仅在本机运行的 macOS 菜单栏应用，用于查看 Codex Token 消耗和额度状态。

## 当前状态

当前仓库包含原生 SwiftUI 工程骨架和静态界面原型，尚未接入真实 Codex 数据。

## 环境要求

- macOS 14 或更高版本
- Xcode 26.6 或兼容的 Swift 6 Xcode 版本
- 首次使用前打开一次 Xcode，接受 License 并安装所需组件

## 开发命令

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -derivedDataPath /private/tmp/SpendScope-DerivedData test
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

运行脚本会构建并启动 `/private/tmp/SpendScope-DerivedData/Build/Products/Debug/SpendScope.app`。Debug Bundle 使用本地签名，仅用于开发，尚未进行发布公证。

## 工程结构

- `Sources/SpendScope/App`：应用入口和生命周期
- `Sources/SpendScope/Features`：菜单栏、看板和设置界面
- `Sources/SpendScope/Models`：领域模型与原型数据
- `Sources/SpendScope/Support`：格式化和设计系统
- `Tests/SpendScopeTests`：单元测试
- `SpendScope.xcodeproj`：Xcode 工程与共享 Scheme
- `script/build_and_run.sh`：统一 Xcode 构建运行入口
- `docs/superpowers/specs`：产品与技术设计
- `docs/superpowers/plans`：实施计划
````

- [ ] **Step 4：执行完整验证**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -derivedDataPath /private/tmp/SpendScope-DerivedData test
./script/build_and_run.sh --verify
```

预期：测试通过、构建通过、`/private/tmp/SpendScope-DerivedData/Build/Products/Debug/SpendScope.app` 存在，应用启动后 `pgrep -x SpendScope` 成功。

- [ ] **Step 5：提交构建与开发体验**

```bash
git add script .codex README.md
git commit -m "chore: add macOS build and run workflow"
```

## 完成定义

- Xcode Scheme 的单元测试通过。
- Xcode Debug 构建通过。
- Xcode 产出的 `SpendScope.app` 能启动并通过进程验证。
- 菜单栏出现 SpendScope 状态项。
- 点击菜单栏可以看到静态额度与 Token 摘要。
- “打开看板”可以激活详细看板窗口。
- 设置入口可以打开原生设置窗口。
- 工程不包含第三方依赖或真实 Codex 数据读取逻辑。
