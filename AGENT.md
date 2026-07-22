# SpendScope Agent 开发指南

本文档用于约束在 SpendScope 仓库中工作的自动化开发 Agent。开始修改前先阅读本文件；涉及架构、统计口径、存储或发布流程时，同时阅读 `docs/TECHNICAL_ARCHIVE.md`。

## 1. 项目目标

SpendScope 是一款原生 macOS 菜单栏应用，用于读取本机 Codex CLI 和 Codex Desktop 产生的记录，并展示 Token 用量、5 小时与 7 天额度、趋势、活动/项目/模型排行和 API 等值费用估算。

必须保持以下产品边界：

- 所有统计和导入进度只保存在本机。
- 不读取、保存或上传提示词、回复、摘要、推理正文、工具输入、文件内容和项目代码。
- 不读取认证文件内容，不保存原始 Git remote 或完整项目路径。
- 不修改或删除 Codex 原始文件和数据库。
- 不把 API 等值费用估算描述为 Codex 实际账单；暂不实现账单对账、预算管理、API Key 实际消费分析、账号体系、云同步或跨设备汇总。

## 2. 技术基线

- 平台：macOS 14.0 及以上。
- 工程：`SpendScope.xcodeproj`，共享 Scheme 为 `SpendScope`。
- 语言：Swift 6。
- UI：SwiftUI、AppKit、Swift Charts。
- 并发与状态：Swift Concurrency、Observation。
- 存储：系统 SQLite3，不依赖第三方包。
- Bundle ID：`com.ychp.SpendScope`。
- 发布架构：Universal Binary，必须同时包含 `arm64` 和 `x86_64`。
- 发布渠道：GitHub Releases；当前 DMG 未签名、未公证。

不要无充分理由引入第三方依赖、额外构建系统或新的持久化框架。确需引入时，先说明体积、隐私、Universal 架构和长期维护影响。

## 3. 目录职责

```text
Config/Version.xcconfig    工程与发布版本的唯一来源
Sources/SpendScope/
├── App/                  应用入口、生命周期、共享状态和额度提醒
├── Data/
│   ├── Codex/            来源发现、事件解码、增量导入和会话归约
│   ├── Dashboard/        看板与会话查询
│   └── Storage/          SQLite、迁移、事件、聚合和检查点
├── Features/
│   ├── Dashboard/        详细看板、日历、活动/项目/模型排行和费用明细
│   ├── MenuBar/          状态栏项目和弹窗
│   └── Settings/         设置窗口
├── Models/               UI 与查询层共享模型
├── Resources/            App、状态栏和 Codex 图标
└── Support/              偏好、更新、提醒、模型价格、格式化和设计系统

Tests/SpendScopeTests/    XCTest 单元与集成测试
script/                   构建、运行、日志和版本说明脚本
.github/workflows/        GitHub Actions 测试与发布流程
docs/                     截图和技术档案
```

核心数据链路入口：

| 领域 | 入口文件 |
| --- | --- |
| 数据源发现 | `Sources/SpendScope/Data/Codex/CodexSourceDiscovery.swift` |
| 官方额度读取 | `Sources/SpendScope/Data/Codex/CodexAccountRateLimitReader.swift` |
| 增量 JSONL 读取 | `Sources/SpendScope/Data/Codex/IncrementalJSONLReader.swift` |
| 事件白名单解码 | `Sources/SpendScope/Data/Codex/CodexEventDecoder.swift` |
| Token 增量计算 | `Sources/SpendScope/Data/Codex/UsageAccumulator.swift` |
| 幂等导入 | `Sources/SpendScope/Data/Codex/CodexImporter.swift` |
| SQLite 存储 | `Sources/SpendScope/Data/Storage/UsageStore.swift` |
| 看板查询 | `Sources/SpendScope/Data/Dashboard/DashboardQueryService.swift` |
| 模型价格 | `Sources/SpendScope/Support/ModelPricing.swift` |
| 模型排行界面 | `Sources/SpendScope/Features/Dashboard/ModelUsagePanel.swift` |
| 全局界面状态 | `Sources/SpendScope/App/DashboardStore.swift` |
| 软件更新 | `Sources/SpendScope/Support/AppUpdateService.swift` |

## 4. 不可破坏的实现约束

### 数据与隐私

- 只解码统计白名单中的最小字段；不要为调试方便把完整 JSON、消息正文或工具参数写入日志或数据库。
- Codex SQLite 必须只读访问。索引不可用时应降级到文件系统发现，不能阻断全部导入。
- 项目身份只保存派生 ID、展示名和哈希指纹，不保存原始 remote 和完整路径。
- 测试只能使用匿名合成数据，不能提交真实 rollout、认证信息或对话内容。

### Token 统计

- `total_token_usage` 是线程内累计快照，必须计算正增量，不能逐条直接求和。
- 计数回退时开启新分段，不能产生负 Token。
- 四类 Token 必须保持互不重叠：未缓存输入、缓存输入、可见输出、推理输出。
- 每日统计继续按 UTC 日期归属，除非产品明确改变口径并同步迁移、测试和文档。
- 额度按 `window_minutes` 识别：300 分钟对应 5 小时，10080 分钟对应 7 天。
- 额度过期且没有新观测时不得推断为 100%。
- 官方额度通过本机 Codex app-server 单独读取并缓存；用量刷新不得顺带无条件触发额度读取。应用启动和用户手动刷新时强制读取一次额度；用量指纹变化和失败重试使用待刷新标记。
- API 等值费用只能使用显式收录的模型价格；未知模型必须保持未定价，不能按相似名称猜价。长上下文、缓存写入等无法从聚合事件可靠还原的附加倍率不得计入总额。

### 增量导入与存储

- 文件检查点只能推进到已完整提交的换行之后；半行留待下次读取。
- 文件移动、归档、重复扫描和应用重启不得重复累计同一事件。
- 事件、聚合、上下文和检查点应在同一事务中提交，失败时整体回滚。
- 修改表结构时增加显式迁移，并覆盖旧数据库升级路径；不要直接假设全新数据库。
- 手动刷新、自动刷新和全量重建必须共享同一统计口径。

### UI 与状态

- 生产界面不得使用静态预览数字兜底。
- 加载、正常、空、过期、失败和不兼容状态要保持可区分。
- 菜单栏、弹窗、看板和设置应继续复用共享状态与设计系统，避免平行实现同一指标或格式。
- 新增用户设置时，补充默认值、持久化、界面入口和相关测试。

## 5. 开发流程

修改前：

1. 确认改动属于采集、标准化、存储查询、状态还是展示层。
2. 阅读相邻实现和对应测试，优先沿用现有模型与命名。
3. 涉及统计口径、隐私边界、数据库或发布产物时，先检查技术档案中的相关约束。

修改时：

- 保持改动聚焦，不顺带重构无关模块。
- 优先修复根因，不在 UI 层掩盖数据层错误。
- 对未知或未来 Codex 字段采取安全降级，不猜测业务语义。
- 保留工作区中已有的无关改动，不覆盖或删除不属于当前任务的内容。
- 不提交 `.build/`、`DerivedData/`、`xcuserdata/`、`.DS_Store`、DMG 或其他生成文件。

修改后：

1. 运行与改动最接近的测试。
2. 数据口径、导入或存储变更应运行完整测试。
3. 构建或界面变更至少执行一次构建；需要实际启动时使用项目脚本。
4. 同步更新受影响的 README、技术档案或发布说明。
5. 检查 `git diff --check` 和最终 diff，确认没有敏感数据及无关文件。

## 6. 构建、运行和测试

统一使用项目脚本构建并启动：

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

调试和日志：

```bash
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

完整测试：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpendScope.xcodeproj \
  -scheme SpendScope \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath /private/tmp/SpendScope-Tests \
  test
```

验证原则：

- 纯文档改动：检查链接、命令、Markdown 和 `git diff --check`。
- UI 或格式化改动：运行相关测试并构建 App；必要时启动验证。
- 解码、Token、导入、SQLite、查询或迁移改动：运行完整 XCTest。
- 发布工作流改动：解析 YAML，检查所有 Shell 片段，并本地运行可独立执行的脚本。
- 不要声称未实际执行的构建、测试、启动或发布已经成功。

## 7. 发布约束

发布入口为 `.github/workflows/unsigned-release.yml`，只能在明确要求发布时触发。

- `Config/Version.xcconfig` 是工程版本的唯一来源；不得在 `project.pbxproj`、Swift 源码或文档中重复维护当前版本字面量。
- 发布前更新并提交 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`；工作流只读取当前提交中的配置，不自动修改或推送版本文件。
- Release Tag 由 `MARKETING_VERSION` 自动生成，必须指向触发工作流的 `GITHUB_SHA`。
- 正式标签使用 `v<语义化版本>`；预发布标签固定使用 `v<版本>-beta`。
- 已存在的同版本 Release 默认不得覆盖；仅修复发布附件时可显式启用 `replace_existing`。
- Release App 必须使用 `ARCHS='arm64 x86_64'`、`ONLY_ACTIVE_ARCH=NO` 构建，并通过 `lipo` 验证。
- Release 标题固定为 `SpendScope v<版本号>`。
- 工作流只上传 `SpendScope-macOS-unsigned.dmg` 和对应 `.sha256`。
- ZIP 与 tar.gz 源码包使用 GitHub 根据标签自动生成的附件，不重复上传自定义源码包。
- DMG 校验文件必须只引用同目录下的 DMG 文件名，保证下载后可直接执行 `shasum -a 256 -c`。
- 版本说明必须面向用户，包含版本亮点、安装方法、系统与芯片支持、未签名打开方式、附件说明、已知限制和完整变更链接。
- 当前包未签名、未公证，不得描述为已签名、安全警告已消除或可无提示安装。
- 不要在没有用户明确授权时创建 Tag、Release、推送分支或删除远端附件。

## 8. 文档维护

- `README.md` 面向用户，描述产品能力、安装、隐私、使用、开发和发布方法。
- `docs/TECHNICAL_ARCHIVE.md` 面向开发维护，记录架构、统计口径、迁移、兼容与演进决策。
- 行为发生变化时更新现在时描述，删除已经失效的步骤，不保留互相矛盾的旧说明。
- 新增截图时放入 `docs/images/`，使用稳定、可读的文件名，并在 README 中提供有意义的替代文本。

## 9. 完成交付标准

交付说明应包含：

- 实际完成的结果和涉及的文件。
- 执行过的测试、构建或验证命令及结果。
- 尚未验证的内容和剩余风险。
- 用户下一步需要执行的操作，例如提交、推送或在 GitHub Actions 中触发发布。

不要仅描述计划；在授权范围内完成实现和验证后再交付。
