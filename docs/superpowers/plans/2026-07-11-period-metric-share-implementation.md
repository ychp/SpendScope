# SpendScope 周期分项占比实施计划

**目标：** 按方案 A 为四周期卡片的输入、缓存、输出、推理增加用量占比和细进度条。

**架构：** `PeriodUsage` 提供基于周期总量的安全占比计算，`TokenFormatter` 将比例格式化为一位小数百分比，`DashboardView` 将每个分项组织为名称、用量/占比和进度条三层结构。

**技术栈：** Swift 6、SwiftUI、XCTest、macOS 14+

## 全局约束

- 在 `codex/period-metric-share` 隔离分支与 worktree 中实施。
- 保持 `920 × 620` 无滚动窗口和 260 点顶部复合卡。
- 保持左侧额度区域、菜单栏弹窗和下方图表不变。
- 不提交主工作区中 Xcode 自动格式化的 scheme 差异。
- DerivedData 使用 `/private/tmp/SpendScope-PeriodMetricShare`。

## Task 1：占比计算与格式化

**文件：**

- 修改：`Tests/SpendScopeTests/TokenFormatterTests.swift`
- 修改：`Sources/SpendScope/Models/DashboardSnapshot.swift`
- 修改：`Sources/SpendScope/Support/TokenFormatter.swift`

1. 增加失败测试，要求今日输入占比为 `8_200_000 / 17_000_000`。
2. 增加失败测试，要求零总量返回 0，负值返回 0，超过总量的值返回 1。
3. 增加失败测试，要求占比分别格式化为 `48.2%`、`0.0%` 和 `100.0%`。
4. 运行定向测试，确认因接口缺失而失败。
5. 为 `PeriodUsage` 增加安全占比计算，为 `TokenFormatter` 增加百分比格式化。
6. 重新运行定向测试并确认通过。

## Task 2：方案 A 分项视图

**文件：**

- 修改：`Sources/SpendScope/Features/Dashboard/DashboardView.swift`

1. `periodMetric` 增加当前周期总量参数，并计算安全占比。
2. 分项名称行继续显示彩色圆点和名称。
3. 数值行左侧显示紧凑 Token 用量，右侧显示一位小数占比。
4. 数值行下方增加 3 点高圆角进度条；背景使用低透明度中性色，填充色与分项颜色一致。
5. 保持 2×2 分项布局，压缩内部间距以避免四宫格裁切。
6. 为进度条和分项补充合适的辅助功能标签。

## Task 3：验证与收尾

1. 运行完整 XCTest：

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
     -configuration Debug -destination "platform=macOS,arch=arm64" \
     -derivedDataPath /private/tmp/SpendScope-PeriodMetricShare test -quiet
   ```

2. 运行 Debug 构建：

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project SpendScope.xcodeproj -scheme SpendScope \
     -configuration Debug -destination "platform=macOS,arch=arm64" \
     -derivedDataPath /private/tmp/SpendScope-PeriodMetricShare build -quiet
   ```

3. 检查 diff，确认无滚动容器、无菜单栏和 scheme 改动。
4. 提交实现分支并进入分支收尾流程。
