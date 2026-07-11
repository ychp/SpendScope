# SpendScope 趋势范围与底部布局实施计划

**目标：** 移除 Token 构成卡，将趋势卡扩展为全宽，把时间范围选择器移入趋势卡标题栏，并让范围选择真正过滤趋势数据。

**架构：** `TrendRange` 枚举定义范围标签、默认值和过滤行为；`DashboardSnapshot.preview` 提供 45 天确定性预览数据；`DashboardView` 只持有趋势范围状态并展示过滤结果，顶部额度与周期指标继续读取原始快照。

**技术栈：** Swift 6、SwiftUI、Swift Charts、XCTest、macOS 14+

## 全局约束

- 在 `codex/trend-range-layout` 隔离分支与 worktree 中实施。
- 保持 `920 × 620` 无滚动窗口和现有顶部复合卡。
- 不修改菜单栏弹窗、额度模型或四周期统计行为。
- 不提交主工作区中 Xcode 自动格式化的 scheme 差异。
- DerivedData 使用 `/private/tmp/SpendScope-TrendRangeLayout`。

## Task 1：趋势范围过滤

**文件：**

- 修改：`Tests/SpendScopeTests/TokenFormatterTests.swift`
- 修改：`Sources/SpendScope/Models/DashboardSnapshot.swift`

1. 增加失败测试，要求默认范围为 7 天，标签顺序为今日、7 天、30 天、全部。
2. 增加失败测试，使用 45 条有序数据验证 1、7、30 和全部的过滤数量及末尾数据保留。
3. 增加失败测试，验证数据不足与空数组不会报错或补零。
4. 运行定向测试并确认因 `TrendRange` 缺失而失败。
5. 增加 `TrendRange` 枚举及过滤方法。
6. 将预览日用量扩展为从 2026-05-28 到 2026-07-11 的 45 条确定性数据。
7. 重新运行定向测试并确认通过。

## Task 2：全宽趋势卡布局

**文件：**

- 修改：`Sources/SpendScope/Features/Dashboard/DashboardView.swift`

1. 将选择状态从字符串改为 `TrendRange`，默认使用 `.sevenDays`。
2. 从页面顶部标题区移除分段选择器。
3. 删除底部 HStack、`compositionCard`、`breakdownItems` 和 `BreakdownDisplayItem`。
4. 让趋势卡占满底部可用宽度和高度。
5. 在趋势卡标题栏左侧显示标题、右侧显示 260 点宽分段选择器。
6. 图表数据源改为当前范围过滤后的 `dailyUsage`。
7. 移除趋势图固定 180 点高度，让图表填满卡片剩余空间。

## Task 3：验证与收尾

1. 运行完整 XCTest：

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
     -configuration Debug -destination "platform=macOS,arch=arm64" \
     -derivedDataPath /private/tmp/SpendScope-TrendRangeLayout test -quiet
   ```

2. 运行 Debug 构建：

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
     -configuration Debug -destination "platform=macOS,arch=arm64" \
     -derivedDataPath /private/tmp/SpendScope-TrendRangeLayout build -quiet
   ```

3. 检查 diff，确认无滚动容器、无菜单栏和 scheme 改动。
4. 提交实现分支并进入分支收尾流程。
