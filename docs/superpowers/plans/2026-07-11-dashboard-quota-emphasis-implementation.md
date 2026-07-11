# SpendScope 额度与周期指标强化实施计划

**目标：** 按已确认原型提高顶部复合卡高度，将额度百分比放入双环圆心、重置时间移到圆环下方，并将四周期分项改为 2×2 两行布局。

**架构：** 保持 `DashboardSnapshot` 和 `DashboardView` 的现有职责。额度模型新增稳定的短周期展示值，预览数据直接提供不含“重置”的最终时间文本；视图只负责同心环、重置时间与周期四宫格的组合。窗口继续使用 `920 × 620` 无滚动布局。

**技术栈：** Swift 6、SwiftUI、Swift Charts、XCTest、macOS 14+

## 全局约束

- 在 `codex/dashboard-quota-emphasis` 隔离分支和 worktree 中实施。
- 保持详细窗口默认与最小尺寸 `920 × 620`。
- 不引入 `ScrollView`，不修改菜单栏弹窗。
- 不提交主工作区中 Xcode 自动格式化的 scheme 差异。
- DerivedData 使用 `/private/tmp/SpendScope-DashboardQuotaEmphasis`。

## Task 1：额度展示模型与测试

**文件：**

- 修改：`Tests/SpendScopeTests/TokenFormatterTests.swift`
- 修改：`Sources/SpendScope/Models/DashboardSnapshot.swift`

1. 增加失败测试，要求两档额度分别生成 `5H 85%` 与 `7d 84%`。
2. 增加失败测试，要求预览重置时间为 `02:52` 和 `2026-07-13 10:45`，且不含“重置”。
3. 运行定向测试，确认因短周期展示接口缺失或旧时间文本而失败。
4. 为 `QuotaSnapshot` 增加短周期与圆心展示文本；更新预览重置时间。
5. 重新运行测试，确认通过。

## Task 2：顶部复合卡布局

**文件：**

- 修改：`Sources/SpendScope/Features/Dashboard/DashboardView.swift`

1. 顶部复合卡高度调整为 260 点，左侧额度区域宽度调整为约 340 点。
2. 增大双环并将其略向上布局；圆心以两行显示 `5H 85%` 与 `7d 84%`。
3. 删除环右侧旧图例；在圆环下方以两行显示彩色圆点、周期缩写与重置时间。
4. 周期标题调整为约 14 点半粗体，总量调整为约 24 点粗体。
5. 每个周期的输入、缓存、输出、推理改为 2×2 两行布局。
6. 保持底部 Token 趋势、Token 构成和窗口尺寸不变。

## Task 3：验证与收尾

1. 运行完整 XCTest：

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
     -configuration Debug -destination "platform=macOS,arch=arm64" \
     -derivedDataPath /private/tmp/SpendScope-DashboardQuotaEmphasis test -quiet
   ```

2. 运行 Debug 构建：

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
     -configuration Debug -destination "platform=macOS,arch=arm64" \
     -derivedDataPath /private/tmp/SpendScope-DashboardQuotaEmphasis build -quiet
   ```

3. 检查 diff，确认无滚动容器、无菜单栏改动、无 scheme 格式化差异。
4. 提交实现分支并按分支收尾流程交付。
