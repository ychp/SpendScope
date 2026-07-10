# SpendScope 紧凑看板实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 将详细看板改为 `920 × 620` 的无滚动单页布局，顶部使用 5 小时/7 天同心额度环和今日/7 日/累计三周期 Token 明细。

**架构：** 在 `DashboardSnapshot` 中引入可复用的 `PeriodUsage`，为三个周期提供一致且可验证的统计口径。`DashboardView` 移除滚动容器和模型分布，将顶部两排替换为一张左右复合卡；下方继续保留趋势与 Token 构成。

**技术栈：** Xcode 26.6、Swift 6、SwiftUI、Swift Charts、XCTest、macOS 14+

## 全局约束

- 详细看板默认和最小尺寸均为 `920 × 620`。
- 详细看板不得使用 `ScrollView`，不得出现水平或垂直滚动条。
- 菜单栏弹窗的尺寸和视觉保持不变。
- 外环为紫色 5 小时额度，内环为蓝色 7 天额度。
- 顶部右侧只展示今日、7 日、累计的总量、未缓存输入、缓存输入和输出。
- 顶部不展示总额度进度条或模型分布。
- 下方 Token 构成保留，并将输出拆分为可见输出和推理输出。
- 命令行 DerivedData 使用 `/private/tmp/SpendScope-CompactDashboard`。

---

### Task 1：建立三周期 Token 数据模型

**文件：**

- 修改：`Sources/SpendScope/Models/DashboardSnapshot.swift`
- 修改：`Tests/SpendScopeTests/TokenFormatterTests.swift`

**接口：**

- 产出：`PeriodUsage(id:title:total:uncachedInput:cachedInput:output:reasoning:)`
- 产出：`PeriodUsage.visibleOutput -> Int`
- 产出：`DashboardSnapshot.periods -> [PeriodUsage]`
- 保持：`DashboardSnapshot.todayTokens` 与 `DashboardSnapshot.breakdown`，供菜单栏继续使用。

- [ ] **Step 1：编写失败的数据口径测试**

在 `Tests/SpendScopeTests/TokenFormatterTests.swift` 追加：

```swift
final class DashboardSnapshotTests: XCTestCase {
    func testPreviewPeriodsUseConsistentTotals() {
        XCTAssertEqual(DashboardSnapshot.preview.periods.count, 3)

        for period in DashboardSnapshot.preview.periods {
            XCTAssertEqual(
                period.total,
                period.uncachedInput + period.cachedInput + period.output
            )
        }
    }

    func testTodayBreakdownSplitsReasoningFromOutput() {
        let snapshot = DashboardSnapshot.preview
        let today = snapshot.periods[0]

        XCTAssertEqual(snapshot.todayTokens, today.total)
        XCTAssertEqual(snapshot.breakdown.input, today.uncachedInput)
        XCTAssertEqual(snapshot.breakdown.cachedInput, today.cachedInput)
        XCTAssertEqual(snapshot.breakdown.output, today.output - today.reasoning)
        XCTAssertEqual(snapshot.breakdown.reasoning, today.reasoning)
        XCTAssertEqual(snapshot.breakdown.total, today.total)
    }
}
```

- [ ] **Step 2：运行测试并确认失败**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /private/tmp/SpendScope-CompactDashboard test -quiet
```

预期：测试目标编译失败，提示 `DashboardSnapshot` 没有 `periods`。

- [ ] **Step 3：替换领域模型实现**

将 `Sources/SpendScope/Models/DashboardSnapshot.swift` 替换为：

```swift
import Foundation

struct DashboardSnapshot: Sendable {
    let planName: String
    let updatedText: String
    let periods: [PeriodUsage]
    let quotas: [QuotaSnapshot]
    let models: [ModelUsage]
    let dailyUsage: [DailyUsage]

    var todayTokens: Int { periods[0].total }
    var sevenDayTokens: Int { periods[1].total }
    var totalTokens: Int { periods[2].total }

    var breakdown: TokenBreakdown {
        let today = periods[0]
        return TokenBreakdown(
            input: today.uncachedInput,
            cachedInput: today.cachedInput,
            output: today.visibleOutput,
            reasoning: today.reasoning
        )
    }

    static let preview = DashboardSnapshot(
        planName: "Pro",
        updatedText: "刚刚刷新",
        periods: [
            PeriodUsage(
                id: "today", title: "今日", total: 17_000_000,
                uncachedInput: 8_200_000, cachedInput: 7_900_000,
                output: 900_000, reasoning: 200_000
            ),
            PeriodUsage(
                id: "sevenDays", title: "7 日", total: 84_200_000,
                uncachedInput: 35_200_000, cachedInput: 45_500_000,
                output: 3_500_000, reasoning: 900_000
            ),
            PeriodUsage(
                id: "allTime", title: "累计", total: 326_800_000,
                uncachedInput: 128_000_000, cachedInput: 184_000_000,
                output: 14_800_000, reasoning: 3_400_000
            )
        ],
        quotas: [
            QuotaSnapshot(id: "5h", title: "5 小时", remaining: 0.85, resetText: "02:52 重置"),
            QuotaSnapshot(id: "7d", title: "7 天", remaining: 0.84, resetText: "周一 10:45 重置")
        ],
        models: [
            ModelUsage(id: "gpt-5.5", name: "gpt-5.5", share: 0.68),
            ModelUsage(id: "gpt-5.4", name: "gpt-5.4", share: 0.32)
        ],
        dailyUsage: [
            DailyUsage(id: "5/10", day: "5/10", total: 8_400_000),
            DailyUsage(id: "5/11", day: "5/11", total: 10_300_000),
            DailyUsage(id: "5/12", day: "5/12", total: 11_100_000),
            DailyUsage(id: "5/13", day: "5/13", total: 12_500_000),
            DailyUsage(id: "5/14", day: "5/14", total: 13_700_000),
            DailyUsage(id: "5/15", day: "5/15", total: 14_200_000),
            DailyUsage(id: "5/16", day: "5/16", total: 14_000_000)
        ]
    )
}

struct PeriodUsage: Identifiable, Sendable {
    let id: String
    let title: String
    let total: Int
    let uncachedInput: Int
    let cachedInput: Int
    let output: Int
    let reasoning: Int

    var visibleOutput: Int { max(0, output - reasoning) }
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

- [ ] **Step 4：运行测试并确认通过**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /private/tmp/SpendScope-CompactDashboard test -quiet
```

预期：`TokenFormatterTests` 和 `DashboardSnapshotTests` 全部通过。

- [ ] **Step 5：提交数据模型增量**

```bash
git add Sources/SpendScope/Models/DashboardSnapshot.swift Tests/SpendScopeTests/TokenFormatterTests.swift
git commit -m "feat: add period token usage model"
```

### Task 2：实现无滚动紧凑看板

**文件：**

- 修改：`Sources/SpendScope/App/SpendScopeApp.swift`
- 修改：`Sources/SpendScope/Support/DesignSystem.swift`
- 修改：`Sources/SpendScope/Features/Dashboard/DashboardView.swift`

**接口：**

- 消费：`DashboardSnapshot.periods`
- 消费：`DashboardSnapshot.quotas`
- 产出：`View.dashboardCard(padding:)`
- 产出：`DashboardView` 的同心额度环、三周期指标和无滚动固定布局。

- [ ] **Step 1：让卡片支持局部紧凑内边距**

将 `DashboardCard` 和扩展改为：

```swift
struct DashboardCard: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(SpendScopeTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08))
            }
    }
}

extension View {
    func dashboardCard(padding: CGFloat = 18) -> some View {
        modifier(DashboardCard(padding: padding))
    }
}
```

菜单栏继续调用 `.dashboardCard()`，因此保持原 18 点内边距；详细看板调用 `.dashboardCard(padding: 12)`。

- [ ] **Step 2：调整详细窗口默认尺寸**

在 `Sources/SpendScope/App/SpendScopeApp.swift` 中将：

```swift
.defaultSize(width: 1080, height: 760)
```

改为：

```swift
.defaultSize(width: 920, height: 620)
```

- [ ] **Step 3：替换详细看板根布局与顶部区域**

`DashboardView.body` 使用以下结构，不得包含 `ScrollView`：

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 10) {
        dashboardHeader
        overviewCard
            .frame(height: 190)
        HStack(alignment: .top, spacing: 10) {
            trendCard.frame(maxWidth: .infinity, maxHeight: .infinity)
            compositionCard
                .frame(width: 300)
                .frame(maxHeight: .infinity)
        }
    }
    .padding(16)
    .frame(minWidth: 920, minHeight: 620)
    .background(Color(nsColor: .windowBackgroundColor))
}
```

顶部复合卡按以下组件边界实现：

```swift
private var overviewCard: some View {
    HStack(spacing: 14) {
        currentQuotaSection
            .frame(width: 280)
        Divider()
        periodMetricsSection
    }
    .dashboardCard(padding: 12)
}

private var currentQuotaSection: some View {
    HStack(spacing: 14) {
        ZStack {
            quotaRing(snapshot.quotas[0], diameter: 128, lineWidth: 10, color: SpendScopeTheme.accent)
            quotaRing(snapshot.quotas[1], diameter: 86, lineWidth: 8, color: SpendScopeTheme.accentBlue)
            VStack(spacing: 1) {
                Text("当前额度").font(.caption2).foregroundStyle(.secondary)
                Text(snapshot.planName).font(.headline)
            }
        }
        .frame(width: 132, height: 132)

        VStack(alignment: .leading, spacing: 12) {
            quotaLegend(snapshot.quotas[0], color: SpendScopeTheme.accent)
            quotaLegend(snapshot.quotas[1], color: SpendScopeTheme.accentBlue)
        }
    }
}

private func quotaRing(
    _ quota: QuotaSnapshot,
    diameter: CGFloat,
    lineWidth: CGFloat,
    color: Color
) -> some View {
    ZStack {
        Circle().stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)
        Circle()
            .trim(from: 0, to: quota.remaining)
            .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
    .frame(width: diameter, height: diameter)
}

private func quotaLegend(_ quota: QuotaSnapshot, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(quota.title).font(.caption.bold())
        }
        Text("\(quota.remainingPercent)% 剩余").font(.callout.bold()).monospacedDigit()
        Text(quota.resetText).font(.caption2).foregroundStyle(.secondary)
    }
}

private var periodMetricsSection: some View {
    HStack(spacing: 0) {
        ForEach(Array(snapshot.periods.enumerated()), id: \.element.id) { index, period in
            periodColumn(period)
            if index < snapshot.periods.count - 1 {
                Divider().padding(.horizontal, 10)
            }
        }
    }
    .frame(maxWidth: .infinity)
}

private func periodColumn(_ period: PeriodUsage) -> some View {
    VStack(alignment: .leading, spacing: 7) {
        Text(period.title).font(.caption).foregroundStyle(.secondary)
        Text(TokenFormatter.compact(period.total))
            .font(.system(size: 22, weight: .bold))
            .monospacedDigit()
        periodMetric("未缓存", period.uncachedInput, SpendScopeTheme.accent)
        periodMetric("缓存", period.cachedInput, SpendScopeTheme.accentBlue)
        periodMetric("输出", period.output, SpendScopeTheme.output)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func periodMetric(_ title: String, _ value: Int, _ color: Color) -> some View {
    HStack(spacing: 5) {
        Circle().fill(color).frame(width: 6, height: 6)
        Text(title).font(.caption2).foregroundStyle(.secondary)
        Spacer(minLength: 4)
        Text(TokenFormatter.compact(value)).font(.caption).monospacedDigit()
    }
}
```

- [ ] **Step 4：压缩底部图表并移除旧组件**

- 删除 `summaryCards`、`metricCard`、`quotaCard`、`modelCard`。
- `trendCard` 的 Chart 高度由 260 调整为 180，并使用 `.dashboardCard(padding: 12)`。
- `compositionCard` 使用 `.dashboardCard(padding: 12)`，继续展示输入、缓存输入、可见输出和推理。
- 时间范围选择器宽度由 300 调整为 260。

完成后 `Sources/SpendScope/Features/Dashboard/DashboardView.swift` 的完整内容为：

```swift
import Charts
import SwiftUI

struct DashboardView: View {
    let snapshot: DashboardSnapshot
    @State private var selectedRange = "7 天"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            dashboardHeader
            overviewCard.frame(height: 190)
            HStack(alignment: .top, spacing: 10) {
                trendCard.frame(maxWidth: .infinity, maxHeight: .infinity)
                compositionCard
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(minWidth: 920, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var dashboardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SpendScope").font(.title.bold())
                Text("Codex · \(snapshot.planName)  ·  \(snapshot.updatedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("时间范围", selection: $selectedRange) {
                ForEach(["今日", "7 天", "30 天", "全部"], id: \.self) {
                    Text($0)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
    }

    private var overviewCard: some View {
        HStack(spacing: 14) {
            currentQuotaSection.frame(width: 280)
            Divider()
            periodMetricsSection
        }
        .dashboardCard(padding: 12)
    }

    private var currentQuotaSection: some View {
        HStack(spacing: 14) {
            ZStack {
                quotaRing(snapshot.quotas[0], diameter: 128, lineWidth: 10, color: SpendScopeTheme.accent)
                quotaRing(snapshot.quotas[1], diameter: 86, lineWidth: 8, color: SpendScopeTheme.accentBlue)
                VStack(spacing: 1) {
                    Text("当前额度").font(.caption2).foregroundStyle(.secondary)
                    Text(snapshot.planName).font(.headline)
                }
            }
            .frame(width: 132, height: 132)

            VStack(alignment: .leading, spacing: 12) {
                quotaLegend(snapshot.quotas[0], color: SpendScopeTheme.accent)
                quotaLegend(snapshot.quotas[1], color: SpendScopeTheme.accentBlue)
            }
        }
    }

    private func quotaRing(
        _ quota: QuotaSnapshot,
        diameter: CGFloat,
        lineWidth: CGFloat,
        color: Color
    ) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: quota.remaining)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private func quotaLegend(_ quota: QuotaSnapshot, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(quota.title).font(.caption.bold())
            }
            Text("\(quota.remainingPercent)% 剩余")
                .font(.callout.bold())
                .monospacedDigit()
            Text(quota.resetText).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var periodMetricsSection: some View {
        HStack(spacing: 0) {
            ForEach(snapshot.periods) { period in
                periodColumn(period)
                if period.id != snapshot.periods.last?.id {
                    Divider().padding(.horizontal, 10)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func periodColumn(_ period: PeriodUsage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(period.title).font(.caption).foregroundStyle(.secondary)
            Text(TokenFormatter.compact(period.total))
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
            periodMetric("未缓存", period.uncachedInput, SpendScopeTheme.accent)
            periodMetric("缓存", period.cachedInput, SpendScopeTheme.accentBlue)
            periodMetric("输出", period.output, SpendScopeTheme.output)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func periodMetric(_ title: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(TokenFormatter.compact(value)).font(.caption).monospacedDigit()
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token 趋势").font(.headline)
            Chart(snapshot.dailyUsage) { item in
                AreaMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(SpendScopeTheme.accent.opacity(0.12))

                LineMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(SpendScopeTheme.accent)
                .lineStyle(StrokeStyle(lineWidth: 3))

                PointMark(
                    x: .value("日期", item.day),
                    y: .value("Token", item.total)
                )
                .foregroundStyle(SpendScopeTheme.accent)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(TokenFormatter.compact(tokens))
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .dashboardCard(padding: 12)
    }

    private var compositionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token 构成").font(.headline)
            ForEach(breakdownItems) { item in
                VStack(spacing: 5) {
                    HStack {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text(item.title).font(.caption)
                        Spacer()
                        Text(TokenFormatter.compact(item.value)).font(.caption).monospacedDigit()
                    }
                    ProgressView(
                        value: Double(item.value),
                        total: Double(snapshot.breakdown.total)
                    )
                    .tint(item.color)
                }
            }
            Spacer(minLength: 0)
        }
        .dashboardCard(padding: 12)
    }

    private var breakdownItems: [BreakdownDisplayItem] {
        [
            BreakdownDisplayItem(id: "input", title: "未缓存输入", value: snapshot.breakdown.input, color: SpendScopeTheme.accent),
            BreakdownDisplayItem(id: "cached", title: "缓存输入", value: snapshot.breakdown.cachedInput, color: SpendScopeTheme.accentBlue),
            BreakdownDisplayItem(id: "output", title: "可见输出", value: snapshot.breakdown.output, color: SpendScopeTheme.output),
            BreakdownDisplayItem(id: "reasoning", title: "推理输出", value: snapshot.breakdown.reasoning, color: SpendScopeTheme.reasoning)
        ]
    }
}

private struct BreakdownDisplayItem: Identifiable {
    let id: String
    let title: String
    let value: Int
    let color: Color
}
```

- [ ] **Step 5：构建并验证没有滚动容器**

运行：

```bash
! rg -n "ScrollView" Sources/SpendScope/Features/Dashboard/DashboardView.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /private/tmp/SpendScope-CompactDashboard build -quiet
```

预期：`rg` 无匹配，Xcode 构建成功。

- [ ] **Step 6：提交紧凑看板布局**

```bash
git add Sources/SpendScope/App/SpendScopeApp.swift \
  Sources/SpendScope/Support/DesignSystem.swift \
  Sources/SpendScope/Features/Dashboard/DashboardView.swift
git commit -m "feat: compact the detailed dashboard"
```

### Task 3：执行完整验证

**文件：** 无新增文件。

**接口：** 验证已有 Xcode Scheme、构建脚本和应用 Bundle。

- [ ] **Step 1：运行完整单元测试**

运行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /private/tmp/SpendScope-CompactDashboard test -quiet
```

预期：所有测试通过，0 failures。

- [ ] **Step 2：构建并启动应用**

运行：

```bash
SPENDSCOPE_DERIVED_DATA=/private/tmp/SpendScope-CompactDashboard \
  ./script/build_and_run.sh --verify
```

预期：输出 `SpendScope is running.`。

- [ ] **Step 3：检查窗口约束与工作区**

运行：

```bash
rg -n "defaultSize\(width: 920, height: 620\)|minWidth: 920, minHeight: 620" Sources/SpendScope
git diff --check
git status -sb
```

预期：两处尺寸约束均命中，无格式错误，工作区干净。
