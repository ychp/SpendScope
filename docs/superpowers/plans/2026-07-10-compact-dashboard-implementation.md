# SpendScope 四周期紧凑看板实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 在现有 `920 × 620` 无滚动看板基础上，将额度区加宽到 330 点，并把右侧三周期横排升级为今日、7 日、30 日、累计的 2×2 四宫格。

**架构：** `DashboardSnapshot.periods` 从三个周期扩展为四个周期，并保证输入、缓存、可见输出和推理之和等于总量。`DashboardView` 保留同心双环和下方图表，只替换复合卡的左右尺寸与右侧周期展示组件。

**技术栈：** Xcode 26.6、Swift 6、SwiftUI、Swift Charts、XCTest、macOS 14+

## 全局约束

- 详细看板默认和最小尺寸保持 `920 × 620`。
- 详细看板不得使用 `ScrollView`。
- 左侧额度区固定宽度为 330 点。
- 外层 5 小时环直径为 138 点，内层 7 天环直径为 92 点。
- 右侧周期顺序固定为：左上今日、右上 7 日、左下 30 日、右下累计。
- 每个宫格展示周期名称、Token 总量、输入、缓存、输出、推理。
- 输入表示未缓存输入；输出表示不含推理的可见输出。
- 输入 + 缓存 + 输出 + 推理必须等于周期 Token 总量。
- 下方 Token 趋势与 Token 构成保持不变。
- DerivedData 使用 `/private/tmp/SpendScope-FourPeriodGrid`。

---

### Task 1：将周期模型扩展到 30 日

**文件：**

- 修改：`Tests/SpendScopeTests/TokenFormatterTests.swift`
- 修改：`Sources/SpendScope/Models/DashboardSnapshot.swift`

**接口：**

- 保持：`DashboardSnapshot.periods -> [PeriodUsage]`
- 新增：`DashboardSnapshot.thirtyDayTokens -> Int`
- 调整：`DashboardSnapshot.totalTokens` 从 `periods[2]` 改为 `periods[3]`。
- 保持：`PeriodUsage.visibleOutput = output - reasoning`。

- [ ] **Step 1：修改测试，要求四周期与四类明细可相加**

将 `DashboardSnapshotTests` 替换为：

```swift
final class DashboardSnapshotTests: XCTestCase {
    func testPreviewPeriodsUseConsistentTotals() {
        let periods = DashboardSnapshot.preview.periods

        XCTAssertEqual(periods.map(\.title), ["今日", "7 日", "30 日", "累计"])
        XCTAssertEqual(periods.count, 4)

        for period in periods {
            XCTAssertEqual(
                period.total,
                period.uncachedInput
                    + period.cachedInput
                    + period.visibleOutput
                    + period.reasoning
            )
        }
    }

    func testTodayBreakdownSplitsReasoningFromOutput() {
        let snapshot = DashboardSnapshot.preview
        let today = snapshot.periods[0]

        XCTAssertEqual(snapshot.todayTokens, today.total)
        XCTAssertEqual(snapshot.thirtyDayTokens, snapshot.periods[2].total)
        XCTAssertEqual(snapshot.totalTokens, snapshot.periods[3].total)
        XCTAssertEqual(snapshot.breakdown.input, today.uncachedInput)
        XCTAssertEqual(snapshot.breakdown.cachedInput, today.cachedInput)
        XCTAssertEqual(snapshot.breakdown.output, today.visibleOutput)
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
  -derivedDataPath /private/tmp/SpendScope-FourPeriodGrid test -quiet
```

预期：`periods.count` 和周期名称断言失败，或编译提示缺少 `thirtyDayTokens`。

- [ ] **Step 3：替换四周期领域模型**

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
    var thirtyDayTokens: Int { periods[2].total }
    var totalTokens: Int { periods[3].total }

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
                id: "thirtyDays", title: "30 日", total: 198_600_000,
                uncachedInput: 78_400_000, cachedInput: 112_100_000,
                output: 8_100_000, reasoning: 1_900_000
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
  -derivedDataPath /private/tmp/SpendScope-FourPeriodGrid test -quiet
```

预期：`TokenFormatterTests` 和 `DashboardSnapshotTests` 共 3 个测试通过。

- [ ] **Step 5：提交四周期数据模型**

```bash
git add Sources/SpendScope/Models/DashboardSnapshot.swift Tests/SpendScopeTests/TokenFormatterTests.swift
git commit -m "feat: add thirty-day token usage"
```

### Task 2：将右侧周期区域改为四宫格

**文件：**

- 修改：`Sources/SpendScope/Features/Dashboard/DashboardView.swift`

**接口：**

- 消费：`DashboardSnapshot.periods`，顺序为今日、7 日、30 日、累计。
- 消费：`PeriodUsage.visibleOutput` 与 `PeriodUsage.reasoning`。
- 产出：左侧 330 点额度区与右侧 2×2 周期四宫格。

- [ ] **Step 1：调整额度区和同心环尺寸**

在 `overviewCard` 中使用：

```swift
currentQuotaSection.frame(width: 330)
```

在 `currentQuotaSection` 中使用：

```swift
quotaRing(
    snapshot.quotas[0],
    diameter: 138,
    lineWidth: 10,
    color: SpendScopeTheme.accent
)
quotaRing(
    snapshot.quotas[1],
    diameter: 92,
    lineWidth: 8,
    color: SpendScopeTheme.accentBlue
)
```

双环容器使用 `.frame(width: 142, height: 142)`。

- [ ] **Step 2：用 2×2 LazyVGrid 替换横向周期列**

删除旧的 `periodColumn` 和 `periodMetric`，加入：

```swift
private var periodGridColumns: [GridItem] {
    [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
}

private var periodMetricsSection: some View {
    LazyVGrid(columns: periodGridColumns, spacing: 8) {
        ForEach(snapshot.periods) { period in
            periodTile(period)
        }
    }
    .frame(maxWidth: .infinity)
}

private func periodTile(_ period: PeriodUsage) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
            Text(period.title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(TokenFormatter.compact(period.total))
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.8)
        }

        HStack(spacing: 6) {
            periodMetric("输入", period.uncachedInput, SpendScopeTheme.accent)
            periodMetric("缓存", period.cachedInput, SpendScopeTheme.accentBlue)
            periodMetric("输出", period.visibleOutput, SpendScopeTheme.output)
            periodMetric("推理", period.reasoning, SpendScopeTheme.reasoning)
        }
    }
    .padding(8)
    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    .overlay {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color.primary.opacity(0.06))
    }
}

private func periodMetric(_ title: String, _ value: Int, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        Text(TokenFormatter.compact(value))
            .font(.caption2)
            .monospacedDigit()
            .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

- [ ] **Step 3：构建并检查布局契约**

运行：

```bash
! rg -n "ScrollView" Sources/SpendScope/Features/Dashboard/DashboardView.swift
rg -n "frame\(width: 330\)|diameter: 138|diameter: 92|LazyVGrid" \
  Sources/SpendScope/Features/Dashboard/DashboardView.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /private/tmp/SpendScope-FourPeriodGrid build -quiet
```

预期：无 `ScrollView`；四项布局约束命中；Xcode 构建成功。

- [ ] **Step 4：提交四宫格布局**

```bash
git add Sources/SpendScope/Features/Dashboard/DashboardView.swift \
  docs/superpowers/plans/2026-07-10-compact-dashboard-implementation.md
git commit -m "feat: add four-period dashboard grid"
```

### Task 3：执行完整验证

**文件：** 无新增文件。

**接口：** 验证 Xcode Scheme、构建脚本、应用 Bundle 和工作区状态。

- [ ] **Step 1：运行完整测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
  -configuration Debug -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /private/tmp/SpendScope-FourPeriodGrid test -quiet
```

预期：3 个测试通过，0 failures。

- [ ] **Step 2：构建并启动应用**

```bash
SPENDSCOPE_DERIVED_DATA=/private/tmp/SpendScope-FourPeriodGrid \
  ./script/build_and_run.sh --verify
```

预期：输出 `SpendScope is running.`。

- [ ] **Step 3：检查最终状态**

```bash
! rg -n "ScrollView" Sources/SpendScope/Features/Dashboard/DashboardView.swift
rg -n "defaultSize\(width: 920, height: 620\)|minWidth: 920, minHeight: 620" Sources/SpendScope
git diff --check
git status -sb
```

预期：无滚动容器，两个窗口尺寸约束命中，无格式错误，工作区干净。
