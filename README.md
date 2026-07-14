# SpendScope

SpendScope 是一款仅在本机运行的 macOS 菜单栏应用，用于查看 Codex Token 用量和额度状态。

## 已实现功能

- 菜单栏显示当前额度摘要，并提供用量弹窗、详细看板和设置入口。
- 详细看板保持 920 × 620 的原生窗口，展示今日、近 7 日、近 30 日和累计四个 Token 周期，以及按日趋势。
- 额度区域展示可用的 5 小时和 7 天窗口、剩余比例与重置时间；额度缺失或过期时显示为空，不使用预览数值补位。
- 支持当前 Codex CLI 与 Codex Desktop 共用的本地 rollout 数据格式，并纳入已归档会话和子代理产生的实际用量。
- 将累计计数转换为未缓存输入、缓存输入、可见输出和推理输出四类互不重叠的 Token 增量。
- 使用事件指纹和文件检查点增量导入，避免重复刷新、活跃会话归档或文件重放造成重复计数。
- 启动后读取上次保存的统计，执行前台刷新并在后台补齐历史；之后每 60 秒自动刷新，也可从菜单弹窗或设置页手动刷新。

## 本地数据与隐私

SpendScope 只读取统计所需的 Codex 本地字段，包括会话来源、模型、套餐、Token 累计计数、额度窗口和明确的会话状态。Codex 的会话文件与线程索引始终以只读方式访问。

应用不会读取或保存认证信息、提示词、消息、标题、回复、摘要、推理正文、工具输入、文件内容或工作目录内容，也不需要 OpenAI 登录态。标准化统计与增量检查点保存在当前用户“应用程序支持”目录下的 SpendScope 本地 SQLite 数据库中，不会上传到网络。

## 当前限制

- 费用估算和账单分析尚未实现。
- 额度通知与系统通知尚未实现。
- 完整会话列表界面尚未实现；当前版本只保存后续安全查询所需的最小会话事实。
- 仅支持当前已识别的 Codex 本地 rollout 与线程索引格式；上游格式发生不兼容变化时会保留已有数据并显示来源异常。
- 缺失或已经过期的额度快照不会推断为满额，只显示为空并等待 Codex 产生新观测。
- 当前工程面向本机开发运行，正式分发所需的开发者身份签名、强化运行时、公证和安装包流程尚未完成。

## 技术说明

- Xcode 26.6
- Swift 6
- SwiftUI、AppKit 与 Swift Charts
- SQLite 3
- XCTest
- macOS 14 及以上版本

项目不包含第三方依赖。

## 首次准备

首次使用 Xcode 时，请先打开一次 `/Applications/Xcode.app`，接受许可协议并完成组件安装。

构建脚本通过 `DEVELOPER_DIR` 使用 `/Applications/Xcode.app/Contents/Developer`，不要求修改全局 `xcode-select` 配置。

## 开发命令

运行完整调试测试：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj \
  -scheme SpendScope \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /private/tmp/SpendScope-DataCapture \
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

其他调试模式：

```bash
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

默认派生数据目录位于 `/private/tmp/SpendScope-DerivedData`。如需覆盖：

```bash
SPENDSCOPE_DERIVED_DATA=/path/to/DerivedData ./script/build_and_run.sh
```

派生数据不默认写入仓库，是因为“文稿”目录可能由 macOS 文件提供程序管理，其扩展属性会影响本地代码签名。

## 工程结构

- `SpendScope.xcodeproj`：Xcode 工程与共享构建方案
- `Sources/SpendScope/App`：应用入口、共享数据状态和生命周期
- `Sources/SpendScope/Data`：Codex 来源发现、增量导入、本地存储与看板查询
- `Sources/SpendScope/Features`：菜单栏、详细看板和设置界面
- `Sources/SpendScope/Models`：看板领域模型
- `Sources/SpendScope/Support`：格式化与设计系统
- `Tests/SpendScopeTests`：匿名夹具和单元测试
- `script/build_and_run.sh`：统一构建运行入口
- `.codex/environments/environment.toml`：Codex 运行操作
- `docs/superpowers/specs`：产品与技术设计
- `docs/superpowers/plans`：实施计划
