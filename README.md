# SpendScope

SpendScope 是一款仅在本机运行的 macOS 菜单栏应用，用于查看 Codex Token 消耗和额度状态。

## 当前状态

当前仓库包含标准 Xcode macOS App 工程和静态界面原型，已具备：

- 菜单栏额度摘要；
- Token 分类摘要；
- 原生详细看板窗口；
- Swift Charts 时间趋势；
- 模型分布与 Token 构成；
- 原生设置窗口。

真实 Codex 数据采集、本地数据库和额度通知尚未接入，界面当前使用静态原型数据。

## 技术栈

- Xcode 26.6
- Swift 6
- SwiftUI
- AppKit
- Swift Charts
- XCTest
- macOS 14+

项目不包含第三方依赖。

## 首次准备

首次使用 Xcode 时，请先打开一次 `/Applications/Xcode.app`，接受 License 并完成组件安装。

构建脚本会通过 `DEVELOPER_DIR` 使用 `/Applications/Xcode.app/Contents/Developer`，不要求修改全局 `xcode-select` 配置。

## 开发命令

运行单元测试：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj \
  -scheme SpendScope \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath /private/tmp/SpendScope-DerivedData \
  test
```

构建并运行：

```bash
./script/build_and_run.sh
```

构建、启动并验证进程：

```bash
./script/build_and_run.sh --verify
```

其他模式：

```bash
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

默认 DerivedData 位于 `/private/tmp/SpendScope-DerivedData`。如需覆盖：

```bash
SPENDSCOPE_DERIVED_DATA=/path/to/DerivedData ./script/build_and_run.sh
```

之所以不默认放在仓库目录，是因为 `Documents` 可能由 macOS File Provider 管理，其扩展属性会导致本地代码签名失败。

## 工程结构

- `SpendScope.xcodeproj`：Xcode 工程与共享 Scheme
- `Sources/SpendScope/App`：应用入口和生命周期
- `Sources/SpendScope/Features`：菜单栏、看板和设置界面
- `Sources/SpendScope/Models`：领域模型与原型数据
- `Sources/SpendScope/Support`：格式化和设计系统
- `Tests/SpendScopeTests`：单元测试
- `script/build_and_run.sh`：统一 Xcode 构建运行入口
- `.codex/environments/environment.toml`：Codex Run 动作
- `docs/superpowers/specs`：产品与技术设计
- `docs/superpowers/plans`：实施计划

## 发布说明

Debug Bundle 使用本地 ad-hoc 签名，仅用于开发。正式发布仍需配置 Developer ID、Hardened Runtime、公证和 DMG 打包流程。
