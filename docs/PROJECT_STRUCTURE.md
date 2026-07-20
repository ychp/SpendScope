# SpendScope 项目文件结构

更新日期：2026-07-18

本文档说明仓库中每个目录的职责、重要程度和清理边界。重要程度分为三类：

- **核心**：构建 App 或维持正确运行所必需，不能随意删除。
- **工程必备**：不一定进入安装包，但对测试、发布、维护或协作很重要，建议纳入版本控制。
- **可选 / 可再生**：只服务本机工具或由系统、Xcode、构建流程自动生成，可以按需删除，不应提交。

## 1. 根目录总览

| 路径 | 级别 | 作用 | 是否进入 App |
| --- | --- | --- | --- |
| `Config/` | 核心 | 统一管理 App 的版本号和构建号 | 构建时使用 |
| `Sources/` | 核心 | SpendScope 全部生产源码与资源 | 是 |
| `SpendScope.xcodeproj/` | 核心 | Xcode 工程配置、Target、构建设置和共享 Scheme | 构建时使用 |
| `Tests/` | 工程必备 | XCTest 单元与集成测试 | 否 |
| `script/` | 工程必备 | 本地构建运行和版本说明生成脚本 | 否 |
| `.github/` | 工程必备 | GitHub Actions 测试、Universal DMG 打包和 Release 发布 | 否 |
| `docs/` | 工程必备 | 技术档案、结构说明和 README 截图 | 否 |
| `README.md` | 工程必备 | 面向用户的产品、安装、隐私、开发和发布说明 | 否 |
| `AGENT.md` | 工程必备 | 自动化开发 Agent 的项目约束 | 否 |
| `.gitignore` | 工程必备 | 排除构建产物和本机状态 | 否 |
| `.codex/` | 可选 | Codex Desktop 的项目运行按钮配置 | 否 |
| `.git/` | 本地核心 | Git 历史、分支、标签和远端信息；不属于项目源码 | 否 |
| `.worktrees/` | 可选 / 可再生 | 本地 Git worktree 临时目录，目前为空 | 否 |
| `.DS_Store` | 可选 / 可删除 | Finder 自动生成的目录显示元数据 | 否 |

结论：真正决定 App 功能和版本的是 `Config/`、`Sources/` 与 `SpendScope.xcodeproj/`；测试、脚本、工作流和文档不进入安装包，但属于可维护、可发布项目的重要组成部分。

## 2. 生产源码 `Sources/SpendScope/`

整个 `Sources/SpendScope/` 都属于核心代码。它按“应用组合、数据、功能界面、共享模型、资源、基础支持”分层。

| 目录 | 级别 | 主要职责 | 修改注意事项 |
| --- | --- | --- | --- |
| `App/` | 核心 | App 入口、生命周期、全局状态、刷新协调和额度提醒 | 避免创建第二套全局状态 |
| `Data/Codex/` | 核心 | 发现 Codex 数据、只读额度信息、解析 JSONL、计算 Token 增量、归约会话状态并协调导入 | 必须保持隐私白名单和幂等性 |
| `Data/Dashboard/` | 核心 | 从本地数据库生成看板和会话查询结果 | 统计口径应与存储层一致 |
| `Data/Storage/` | 核心 | SQLite 连接、迁移、事务、事件、聚合和文件检查点 | 表结构变化必须提供迁移 |
| `Features/Dashboard/` | 核心 | Token 看板、趋势、日历、活动排行和项目用量 | 不在 UI 中重复计算业务口径 |
| `Features/MenuBar/` | 核心 | 菜单栏状态项及其弹窗 | 与 `DashboardStore` 共享状态 |
| `Features/Settings/` | 核心 | 设置窗口、刷新、提醒、数据来源和更新选项 | 新设置需补默认值与持久化 |
| `Models/` | 核心 | 查询层与界面层共享的数据模型 | 避免放入数据库或 UI 专属逻辑 |
| `Resources/` | 核心 | App 图标、菜单栏图标和 Codex 图标资源 | 删除会造成资源缺失或构建异常 |
| `Support/` | 核心 | 偏好设置、软件更新、设计系统、格式化和提醒模型 | 优先复用，避免各界面自行实现 |

核心数据路径如下：

```text
Codex 本机文件 / 只读索引
        ↓
Data/Codex：发现、读取、解码、增量计算
        ↓
Data/Storage：幂等写入 SpendScope SQLite
        ↓
Data/Dashboard：聚合查询
        ↓
App/DashboardStore：发布共享状态
        ↓
Features：菜单栏、看板和设置
```

最需要谨慎修改的入口：

| 领域 | 文件 |
| --- | --- |
| 数据源发现 | `Sources/SpendScope/Data/Codex/CodexSourceDiscovery.swift` |
| 额度只读补充 | `Sources/SpendScope/Data/Codex/CodexAccountRateLimitReader.swift` |
| 增量文件读取 | `Sources/SpendScope/Data/Codex/IncrementalJSONLReader.swift` |
| 隐私白名单解码 | `Sources/SpendScope/Data/Codex/CodexEventDecoder.swift` |
| Token 增量口径 | `Sources/SpendScope/Data/Codex/UsageAccumulator.swift` |
| 幂等导入 | `Sources/SpendScope/Data/Codex/CodexImporter.swift` |
| 数据库与迁移 | `Sources/SpendScope/Data/Storage/UsageStore.swift` |
| 看板统计 | `Sources/SpendScope/Data/Dashboard/DashboardQueryService.swift` |
| 全局状态 | `Sources/SpendScope/App/DashboardStore.swift` |

## 3. 测试 `Tests/SpendScopeTests/`

`Tests/` 不会被打进 DMG，因此从“运行 App”的角度可以缺少；但它保护 Token 口径、隐私边界、数据库迁移和重复导入，属于工程必备内容，不建议删除。

测试大致对应：

- `CodexEventDecoderTests`：事件白名单、字段兼容和隐私边界。
- `IncrementalJSONLReaderTests`：追加、半行、分块、截断和替换。
- `UsageAccumulatorTests`：累计值转增量、回退分段和 Token 分类。
- `CodexImporterTests`、`UsageStoreTests`：导入幂等、事务、检查点和迁移。
- `DashboardQueryServiceTests`、`SessionQueryServiceTests`：周期统计、额度、排行和会话查询。
- `DashboardStoreTests`：加载、刷新、错误和全局状态协调。
- `UsageReminderTests`、`AppUpdateServiceTests`：提醒阈值和软件更新校验。
- `TokenFormatterTests`、`SessionStateReducerTests`：展示格式与会话事实归约。

数据层、统计层或 SQLite 发生变化时，应运行完整 XCTest，而不是只验证 App 能启动。

## 4. 构建与发布目录

### `SpendScope.xcodeproj/` — 核心

需要提交的文件只有：

- `project.pbxproj`：Target、源码引用、Bundle ID、部署版本和构建设置；Debug / Release 均引用 `Config/Version.xcconfig`。
- `xcshareddata/xcschemes/SpendScope.xcscheme`：CI 与团队共享的 Scheme。

`project.xcworkspace/`、`xcuserdata/` 和 `*.xcuserstate` 是 Xcode 自动生成的用户工作区状态，可删除并重新生成，不应提交。

### `Config/` — 核心

- `Version.xcconfig`：`MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION` 的唯一来源。

新版本只修改这个文件。Xcode 自动将值写入 App Bundle，运行时代码从 Bundle 获取版本，GitHub Actions 也从同一文件生成 Release Tag。

### `script/` — 工程必备

- `build_and_run.sh`：停止旧进程、构建 Debug App、启动、调试和验证进程。
- `generate_release_notes.sh`：将版本亮点整理成结构化 GitHub Release 说明。

这些脚本不是运行时依赖，但统一了本地开发和发布行为，建议保留。

### `.github/workflows/` — 发布必备

`unsigned-release.yml` 负责：

- 从 `Config/Version.xcconfig` 读取版本号和构建号并生成 Tag，无需发布者填写。
- 校验 Xcode 实际构建版本与统一配置一致，并默认阻止覆盖已有版本。
- 运行测试。
- 构建并验证 `arm64 + x86_64` Universal App。
- 生成未签名 DMG 和 SHA-256 校验文件。
- 生成版本说明并创建或更新 GitHub Release。

本地用 Xcode 运行时可以没有 `.github/`，但通过 GitHub 发布正式附件时必须保留。

## 5. 文档与工具配置

### `docs/` — 工程必备

- `TECHNICAL_ARCHIVE.md`：架构、统计口径、迁移、兼容和演进决策。
- `PROJECT_STRUCTURE.md`：本文档，说明文件分级和清理边界。
- `images/`：README 使用的产品截图。

截图不参与 App 构建；如果不需要仓库首页展示可以移除，但必须同步删除 README 引用。

### `.codex/` — 可选

`environments/environment.toml` 为 Codex Desktop 提供 `Run` 操作，命令指向 `./script/build_and_run.sh`。删除后不影响 Xcode、命令行构建或发布，只会失去 Codex 内的快捷运行入口。

### `AGENT.md` — 工程协作文件

记录隐私、Token 统计、数据库、构建和发布约束。它不参与编译，但可避免自动化修改破坏核心口径。若依赖支持自动发现 `AGENTS.md` 的工具，可按工具约定改名；不要同时维护两份内容不同的规则文件。

## 6. 可安全清理的生成物

以下内容均不应提交：

| 路径或模式 | 来源 | 清理影响 |
| --- | --- | --- |
| `.DS_Store` | Finder | 无，可随时删除 |
| `DerivedData/` | Xcode | 下次构建会重新生成，首次构建变慢 |
| `.build/` | Swift 构建工具 | 下次构建会重新生成 |
| `dist/` | 打包流程 | 删除本地 DMG 等产物，不影响源码 |
| `dmg-root/` | DMG 暂存目录 | 无，可重新生成 |
| `SpendScope-release-notes.md` | 发布流程 | 无，可重新生成 |
| `.worktrees/` | 本地 worktree 工具 | 仅在确认没有活跃 worktree 时删除 |
| `SpendScope.xcodeproj/project.xcworkspace/` | Xcode | 用户工作区状态会重建 |
| `xcuserdata/`、`*.xcuserstate` | Xcode | 丢失个人窗口与断点等状态，不影响工程 |

不要清理 `.git/`、`Sources/`、`SpendScope.xcodeproj/project.pbxproj` 或共享 Scheme。清理 `docs/images/`、测试和脚本前，也要先确认不再需要对应文档、质量保障或自动化流程。

## 7. 当前整理建议

当前目录边界清晰，无需进行大规模移动或重命名。建议保持：

1. 生产代码继续只放在 `Sources/SpendScope/` 的既有分层中。
2. 测试文件与被测模块同名，统一放入 `Tests/SpendScopeTests/`。
3. 构建、调试和发布辅助逻辑放在 `script/`，不要混入 App 源码。
4. 用户文档保留在 README，维护细节放入 `docs/`。
5. 本机生成物交给 `.gitignore` 管理，不通过提交“保存”构建结果。
6. 发布附件由 GitHub Actions 生成，不在仓库中新增 `releases/`、DMG 或源码压缩包。
