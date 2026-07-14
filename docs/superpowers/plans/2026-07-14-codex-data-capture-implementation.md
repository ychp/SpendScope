# Codex Data Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从本机 Codex CLI 与 Codex Desktop 的 rollout 数据增量抓取 Token、额度、模型、套餐和会话状态，并直接驱动 SpendScope 菜单栏与详细看板。

**Architecture:** Codex SQLite 只用于线程索引和归档/子代理状态补充，rollout JSONL 是 Token、额度和生命周期事件的事实来源。后台 actor 流式读取新增 JSONL，将最小化事件和检查点原子写入 SpendScope SQLite，再由查询服务生成现有 `DashboardSnapshot`，Main Actor 上的 `DashboardStore` 统一驱动全部 SwiftUI 场景。

**Tech Stack:** macOS 14+、Swift 6、SwiftUI、Observation、Foundation、SQLite3、XCTest、Xcode 26.6；不增加第三方依赖。

## Global Constraints

- Codex 文件与数据库始终只读；不得写入、迁移或长期锁定 `~/.codex`。
- 不读取 `auth.json`、`history.jsonl`，不保存 Prompt、回复、标题、摘要、工具调用或文件内容。
- 统计整数使用 `Int64`，时间以 UTC Unix 毫秒存储，日期边界在查询时按系统时区计算。
- 未缓存输入 = input - cached；可见输出 = output - reasoning；两者最低为 0。
- 套餐缺失或无法确认时归为推断 Free，并保留原始套餐值及推断标志。
- 额度按 `window_minutes` 匹配：300 分钟为 5 小时，10080 分钟为 7 天，不依赖 primary/secondary 顺序。
- 会话状态保存活动、归档和子代理关系三个正交事实；不得根据缺失事件推断失败或完成。
- 生产界面没有真实数据时显示加载、空或错误状态；`DashboardSnapshot.preview` 只用于 Preview 和测试。
- 保持现有 920 × 620 详细看板布局、中文界面和无滚动条设计。
- 每个任务使用 TDD，测试通过后单独提交；不得混入无关格式化或界面重构。

## File Structure

### Production files

- `Sources/SpendScope/Data/Codex/CodexEventModels.swift`：最小化 Codex 事件、Token、额度、套餐和会话状态领域类型。
- `Sources/SpendScope/Data/Codex/CodexEventDecoder.swift`：从单行 JSONL 解码允许的统计事件，忽略消息载荷。
- `Sources/SpendScope/Data/Codex/UsageAccumulator.swift`：累计计数转增量、Token 分类和计数器重置。
- `Sources/SpendScope/Data/Codex/SessionStateReducer.swift`：活动、归档、子代理关系和展示状态的确定性归约。
- `Sources/SpendScope/Data/Storage/SQLiteDatabase.swift`：最小 SQLite3 连接、绑定、查询和事务封装。
- `Sources/SpendScope/Data/Storage/UsageStore.swift`：迁移、事件去重、检查点、聚合与查询事实持久化。
- `Sources/SpendScope/Data/Codex/CodexSourceDiscovery.swift`：Codex 根目录、线程索引和 rollout 文件发现。
- `Sources/SpendScope/Data/Codex/IncrementalJSONLReader.swift`：按字节偏移流式读取完整 JSONL 行。
- `Sources/SpendScope/Data/Codex/CodexImporter.swift`：协调解码、归约和原子批次提交。
- `Sources/SpendScope/Data/Dashboard/DashboardQueryService.swift`：把数据库事实转换为 `DashboardSnapshot`。
- `Sources/SpendScope/Data/Dashboard/SessionQueryService.swift`：查询可筛选的会话状态与新鲜度，不读取对话内容。
- `Sources/SpendScope/App/DashboardStore.swift`：加载状态、首次导入、手动刷新和 60 秒自动刷新。
- `Sources/SpendScope/Models/DashboardSnapshot.swift`：真实快照所需的安全访问器和空数据模型。
- `Sources/SpendScope/App/SpendScopeApp.swift`：注入共享 store，不再创建生产 preview。
- `Sources/SpendScope/Features/Dashboard/DashboardView.swift`：显示真实加载、空、失败和看板状态。
- `Sources/SpendScope/Features/MenuBar/MenuBarPopoverView.swift`：显示真实状态并连接刷新按钮。
- `Sources/SpendScope/Features/Settings/SettingsView.swift`：显示 CLI、Desktop 和索引健康状态。
- `SpendScope.xcodeproj/project.pbxproj`：登记新文件并为应用与测试链接系统 SQLite3。

### Test files

- `Tests/SpendScopeTests/CodexEventDecoderTests.swift`
- `Tests/SpendScopeTests/UsageAccumulatorTests.swift`
- `Tests/SpendScopeTests/SessionStateReducerTests.swift`
- `Tests/SpendScopeTests/UsageStoreTests.swift`
- `Tests/SpendScopeTests/IncrementalJSONLReaderTests.swift`
- `Tests/SpendScopeTests/CodexImporterTests.swift`
- `Tests/SpendScopeTests/DashboardQueryServiceTests.swift`
- `Tests/SpendScopeTests/SessionQueryServiceTests.swift`
- `Tests/SpendScopeTests/DashboardStoreTests.swift`

---

### Task 1: Minimal Codex Event Decoder

**Files:**
- Create: `Sources/SpendScope/Data/Codex/CodexEventModels.swift`
- Create: `Sources/SpendScope/Data/Codex/CodexEventDecoder.swift`
- Create: `Tests/SpendScopeTests/CodexEventDecoderTests.swift`
- Modify: `SpendScope.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `CodexEventDecoder.decode(line:) throws -> CodexDecodedEvent?`
- Produces: `CodexDecodedEvent`, `TokenCounters`, `TokenCounterSnapshot`, `RawQuotaWindow`, `SessionLifecycleEvent`, `CodexSourceKind`

- [ ] **Step 1: Write decoder tests with anonymous JSONL**

```swift
import XCTest
@testable import SpendScope

final class CodexEventDecoderTests: XCTestCase {
    private let decoder = CodexEventDecoder()

    func testDecodesDesktopSessionAndTurnModel() throws {
        let session = #"{"timestamp":"2026-07-14T06:55:00.000Z","type":"session_meta","payload":{"id":"thread-1","source":"vscode","originator":"Codex Desktop","cli_version":"0.144.4","model_provider":"openai"}}"#
        let turn = #"{"timestamp":"2026-07-14T06:55:01.000Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.6-sol"}}"#

        XCTAssertEqual(try decoder.decode(line: Data(session.utf8)), .session(.init(threadID: "thread-1", source: .desktop, formatVersion: "0.144.4")))
        XCTAssertEqual(try decoder.decode(line: Data(turn.utf8)), .turn(.init(turnID: "turn-1", model: "gpt-5.6-sol")))
    }

    func testDecodesTokenCountersQuotasAndPlan() throws {
        let line = #"{"timestamp":"2026-07-14T06:55:23.433Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":32450,"cached_input_tokens":21248,"output_tokens":327,"reasoning_output_tokens":158,"total_tokens":32777}},"rate_limits":{"plan_type":"plus","primary":{"used_percent":15.0,"window_minutes":300,"resets_at":1784600433},"secondary":{"used_percent":16.0,"window_minutes":10080,"resets_at":1785200000}}}}"#

        guard case let .token(snapshot) = try decoder.decode(line: Data(line.utf8)) else {
            return XCTFail("Expected token event")
        }
        XCTAssertEqual(snapshot.counters, TokenCounters(input: 32_450, cachedInput: 21_248, output: 327, reasoning: 158))
        XCTAssertEqual(snapshot.planRaw, "plus")
        XCTAssertEqual(snapshot.quotas.map(\.windowMinutes), [300, 10_080])
    }

    func testDecodesOnlyWhitelistedLifecycleEventsAndIgnoresMessages() throws {
        let started = #"{"timestamp":"2026-07-14T06:55:02.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1","model_context_window":258400}}"#
        let message = #"{"timestamp":"2026-07-14T06:55:03.000Z","type":"event_msg","payload":{"type":"user_message","message":"must never enter the store"}}"#

        guard case let .lifecycle(event) = try decoder.decode(line: Data(started.utf8)) else {
            return XCTFail("Expected lifecycle event")
        }
        XCTAssertEqual(event.kind, .started)
        XCTAssertNil(try decoder.decode(line: Data(message.utf8)))
    }
}
```

- [ ] **Step 2: Run the decoder tests and verify they fail**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SpendScope.xcodeproj -scheme SpendScope -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/SpendScope-DataCapture \
  test -only-testing:SpendScopeTests/CodexEventDecoderTests -quiet
```

Expected: build fails because `CodexEventDecoder` and event models do not exist.

- [ ] **Step 3: Implement minimal sendable event types and decoder**

Define these exact public-to-module shapes in `CodexEventModels.swift`:

```swift
enum CodexSourceKind: String, Codable, Sendable { case cli, desktop, unknown }
enum PlanKind: String, Codable, Sendable { case free, plus, proLite }

struct SessionMetadata: Equatable, Sendable {
    let threadID: String
    let source: CodexSourceKind
    let formatVersion: String
}

struct TurnContext: Equatable, Sendable {
    let turnID: String
    let model: String
}

struct PlanResolution: Equatable, Sendable {
    let kind: PlanKind
    let rawValue: String?
    let isInferred: Bool
}

struct TokenCounters: Equatable, Sendable {
    let input: Int64
    let cachedInput: Int64
    let output: Int64
    let reasoning: Int64
}

struct RawQuotaWindow: Equatable, Sendable {
    let windowMinutes: Int
    let usedPercent: Double
    let resetsAtSeconds: Int64?
}

struct TokenCounterSnapshot: Equatable, Sendable {
    let observedAtMilliseconds: Int64
    let counters: TokenCounters?
    let planRaw: String?
    let quotas: [RawQuotaWindow]
}

enum SessionLifecycleKind: String, Codable, Sendable {
    case started, completed, interrupted, rolledBack
}

struct SessionLifecycleEvent: Equatable, Sendable {
    let kind: SessionLifecycleKind
    let observedAtMilliseconds: Int64
    let turnID: String?
}

enum CodexDecodedEvent: Equatable, Sendable {
    case session(SessionMetadata)
    case turn(TurnContext)
    case token(TokenCounterSnapshot)
    case lifecycle(SessionLifecycleEvent)
}
```

Implement `CodexEventDecoder` with private `Decodable` envelopes containing only `timestamp`, `type` and the whitelisted payload fields. Parse fractional ISO-8601 timestamps with `ISO8601DateFormatter` configured with `.withInternetDateTime` and `.withFractionalSeconds`. Source classification rules are: `originator == "Codex Desktop"` → desktop; string source `cli` → cli; otherwise unknown. Return nil for every message, reasoning or tool event.

- [ ] **Step 4: Register files and run decoder tests**

Add both production files to the SpendScope Sources phase and the test file to SpendScopeTests Sources in `project.pbxproj`.

Run the Step 2 command. Expected: `CodexEventDecoderTests` passes.

- [ ] **Step 5: Commit decoder slice**

```bash
git add SpendScope.xcodeproj/project.pbxproj Sources/SpendScope/Data/Codex/CodexEventModels.swift Sources/SpendScope/Data/Codex/CodexEventDecoder.swift Tests/SpendScopeTests/CodexEventDecoderTests.swift
git commit -m "feat(data): decode Codex statistics events"
```

### Task 2: Token, Plan, Quota, and Session State Normalization

**Files:**
- Create: `Sources/SpendScope/Data/Codex/UsageAccumulator.swift`
- Create: `Sources/SpendScope/Data/Codex/SessionStateReducer.swift`
- Create: `Tests/SpendScopeTests/UsageAccumulatorTests.swift`
- Create: `Tests/SpendScopeTests/SessionStateReducerTests.swift`
- Modify: `SpendScope.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TokenCounters`, `RawQuotaWindow`, `SessionLifecycleEvent`
- Produces: `UsageAccumulator.delta(previous:current:) -> TokenUsageDelta?`
- Produces: `PlanResolver.resolve(rawValue:) -> PlanResolution`
- Produces: `QuotaNormalizer.normalize(_:plan:observedAtMilliseconds:) -> [QuotaObservation]`
- Produces: `SessionStateReducer.reduce(current:event:eventKey:) -> SessionStateSnapshot`

- [ ] **Step 1: Write failing normalization tests**

```swift
final class UsageAccumulatorTests: XCTestCase {
    func testConvertsCumulativeCountersIntoFourNonOverlappingCategories() {
        let previous = TokenCounters(input: 10_000, cachedInput: 6_000, output: 800, reasoning: 300)
        let current = TokenCounters(input: 16_000, cachedInput: 9_500, output: 1_400, reasoning: 500)

        XCTAssertEqual(
            UsageAccumulator.delta(previous: previous, current: current),
            TokenUsageDelta(uncachedInput: 2_500, cachedInput: 3_500, visibleOutput: 400, reasoning: 200)
        )
    }

    func testCounterRollbackStartsANewSegment() {
        let previous = TokenCounters(input: 50_000, cachedInput: 30_000, output: 4_000, reasoning: 1_000)
        let current = TokenCounters(input: 5_000, cachedInput: 2_000, output: 400, reasoning: 100)

        XCTAssertEqual(UsageAccumulator.delta(previous: previous, current: current)?.total, 5_400)
    }

    func testNormalizesPlansAndQuotaOrder() {
        XCTAssertEqual(PlanResolver.resolve(rawValue: "prolite"), PlanResolution(kind: .proLite, rawValue: "prolite", isInferred: false))
        XCTAssertEqual(PlanResolver.resolve(rawValue: "future-plan"), PlanResolution(kind: .free, rawValue: "future-plan", isInferred: true))

        let raw = [
            RawQuotaWindow(windowMinutes: 10_080, usedPercent: 16, resetsAtSeconds: 200),
            RawQuotaWindow(windowMinutes: 300, usedPercent: 15, resetsAtSeconds: 100)
        ]
        XCTAssertEqual(QuotaNormalizer.normalize(raw, plan: PlanResolver.resolve(rawValue: "plus"), observedAtMilliseconds: 1).map(\.kind), [.weekly, .fiveHour])
    }
}
```

```swift
final class SessionStateReducerTests: XCTestCase {
    func testPreservesActivityAndArchiveAsIndependentFacts() {
        let started = SessionLifecycleEvent(kind: .started, observedAtMilliseconds: 100, turnID: "turn-1")
        let completed = SessionLifecycleEvent(kind: .completed, observedAtMilliseconds: 200, turnID: "turn-1")
        var state = SessionStateSnapshot.empty(threadID: "thread-1")

        state = SessionStateReducer.reduce(current: state, event: started, eventKey: "a:1")
        state = SessionStateReducer.reduce(current: state, event: completed, eventKey: "a:2")
        state = SessionStateReducer.setArchived(current: state, archived: true, observedAtMilliseconds: 300)

        XCTAssertEqual(state.activity, .completed)
        XCTAssertEqual(state.archive, .archived)
        XCTAssertEqual(state.displayState, .archived)
    }

    func testOlderEventsCannotOverwriteNewerStateAndOpenIsNotRunning() {
        var state = SessionStateSnapshot.empty(threadID: "thread-1")
        state = SessionStateReducer.reduce(current: state, event: .init(kind: .completed, observedAtMilliseconds: 200, turnID: "t"), eventKey: "b")
        state = SessionStateReducer.reduce(current: state, event: .init(kind: .started, observedAtMilliseconds: 100, turnID: "t"), eventKey: "a")
        state = SessionStateReducer.setChildEdgeStatus(current: state, status: "open")

        XCTAssertEqual(state.activity, .completed)
        XCTAssertEqual(state.childEdgeStatus, "open")
        XCTAssertNotEqual(state.displayState, .running)
    }
}
```

- [ ] **Step 2: Run reducer tests and verify missing-symbol failures**

Run the Xcode test command from Task 1 with both `-only-testing:SpendScopeTests/UsageAccumulatorTests` and `-only-testing:SpendScopeTests/SessionStateReducerTests`.

Expected: build fails because the normalizers and reducers do not exist.

- [ ] **Step 3: Implement pure normalization logic**

Add these exact types:

```swift
struct TokenUsageDelta: Equatable, Sendable {
    let uncachedInput: Int64
    let cachedInput: Int64
    let visibleOutput: Int64
    let reasoning: Int64
    var total: Int64 { uncachedInput + cachedInput + visibleOutput + reasoning }
}

enum QuotaKind: String, Codable, Sendable { case fiveHour, weekly }
struct QuotaObservation: Equatable, Sendable {
    let kind: QuotaKind
    let observedAtMilliseconds: Int64
    let windowMinutes: Int
    let remaining: Double
    let resetsAtMilliseconds: Int64?
    let plan: PlanResolution
}
```

`UsageAccumulator.delta` subtracts component counters when every current component is greater than or equal to previous; otherwise it treats current as a new segment. It derives uncached and visible values after subtraction and returns nil only for a four-category total of zero.

`PlanResolver` recognizes lowercased `free`, `plus`, and `prolite`; every other value, including nil, maps to inferred Free. `QuotaNormalizer` clamps `1 - usedPercent / 100` into 0...1, recognizes only 300 and 10080 minutes, preserves input order, and converts reset seconds to milliseconds.

Define `SessionActivityState`, `SessionArchiveState`, `SessionDisplayState`, `SessionStateSnapshot` and `SessionStateReducer`. State updates compare `(observedAtMilliseconds, eventKey)` lexicographically. Display priority is archived, running, interrupted, rolledBack, completed, unknown. `childEdgeStatus` never changes activity.

- [ ] **Step 4: Register files and run both test classes**

Expected: all normalization and state tests pass.

- [ ] **Step 5: Commit normalization slice**

```bash
git add SpendScope.xcodeproj/project.pbxproj Sources/SpendScope/Data/Codex/UsageAccumulator.swift Sources/SpendScope/Data/Codex/SessionStateReducer.swift Tests/SpendScopeTests/UsageAccumulatorTests.swift Tests/SpendScopeTests/SessionStateReducerTests.swift
git commit -m "feat(data): normalize usage quotas and session states"
```

### Task 3: SQLite Storage, Migrations, and Idempotent Batches

**Files:**
- Create: `Sources/SpendScope/Data/Storage/SQLiteDatabase.swift`
- Create: `Sources/SpendScope/Data/Storage/UsageStore.swift`
- Create: `Tests/SpendScopeTests/UsageStoreTests.swift`
- Modify: `SpendScope.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: normalized Token, quota and session state types from Tasks 1–2
- Produces: `UsageStore(databaseURL:) throws`
- Produces: `UsageStore.commit(_ batch: ImportBatch) throws`
- Produces: checkpoint and aggregate query methods used by Tasks 4–6

- [ ] **Step 1: Link system SQLite3 and write failing store tests**

Add `-lsqlite3` to `OTHER_LDFLAGS` for SpendScope Debug and Release configurations, then register `SQLiteDatabase.swift`, `UsageStore.swift`, and `UsageStoreTests.swift`.

```swift
final class UsageStoreTests: XCTestCase {
    func testBatchIsIdempotentAndCheckpointAdvancesAtomically() throws {
        let store = try makeStore()
        let event = StoredUsageEvent.fixture(fingerprint: "usage-1", total: 100)
        let batch = ImportBatch(
            file: .fixture(committedOffset: 80),
            usageEvents: [event], quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
        )

        try store.commit(batch)
        try store.commit(batch)

        XCTAssertEqual(try store.totalUsage(), 100)
        XCTAssertEqual(try store.fileCheckpoint(fileID: batch.file.fileID)?.committedOffset, 80)
    }

    func testStoresOrthogonalSessionFactsWithoutMessageColumns() throws {
        let store = try makeStore()
        try store.commit(.fixture(session: .fixture(activity: .completed, archive: .archived, childEdgeStatus: "open")))

        let session = try XCTUnwrap(store.sessions().first)
        XCTAssertEqual(session.activity, .completed)
        XCTAssertEqual(session.archive, .archived)
        XCTAssertEqual(session.childEdgeStatus, "open")
        XCTAssertFalse(try store.schemaColumns(table: "sessions").contains("title"))
        XCTAssertFalse(try store.schemaColumns(table: "sessions").contains("message"))
    }
}
```

- [ ] **Step 2: Run store tests and verify SQLite/store failures**

Run the shared Xcode command with `-only-testing:SpendScopeTests/UsageStoreTests`.

Expected: build fails until the wrapper and store are implemented.

- [ ] **Step 3: Implement the SQLite wrapper and exact version-1 schema**

`SQLiteDatabase` must expose `execute(sql:bindings:)`, `query(sql:bindings:) -> [[String: SQLiteValue]]`, and `inTransaction(_:)`. Use `sqlite3_open_v2` with `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX`, bind Int64/Double/String/null explicitly, finalize every statement with `defer`, and rollback on thrown errors.

Migration version 1 creates:

```sql
CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY);
CREATE TABLE source_files(
  file_id TEXT PRIMARY KEY, device_id INTEGER NOT NULL, inode INTEGER NOT NULL,
  path TEXT NOT NULL, committed_offset INTEGER NOT NULL DEFAULT 0,
  generation INTEGER NOT NULL DEFAULT 0, last_record_at_ms INTEGER,
  last_success_at_ms INTEGER, format_status TEXT NOT NULL DEFAULT 'supported', last_error TEXT
);
CREATE TABLE thread_checkpoints(
  thread_id TEXT PRIMARY KEY, current_model TEXT,
  input_tokens INTEGER, cached_input_tokens INTEGER, output_tokens INTEGER, reasoning_tokens INTEGER,
  counter_segment INTEGER NOT NULL DEFAULT 0, last_token_at_ms INTEGER
);
CREATE TABLE usage_events(
  fingerprint TEXT PRIMARY KEY, observed_at_ms INTEGER NOT NULL, thread_id TEXT NOT NULL,
  source_kind TEXT NOT NULL, model TEXT NOT NULL, plan TEXT NOT NULL, plan_raw TEXT,
  plan_is_inferred INTEGER NOT NULL, uncached_input_tokens INTEGER NOT NULL,
  cached_input_tokens INTEGER NOT NULL, visible_output_tokens INTEGER NOT NULL,
  reasoning_tokens INTEGER NOT NULL, total_tokens INTEGER NOT NULL,
  source_file_id TEXT NOT NULL, source_offset INTEGER NOT NULL
);
CREATE INDEX usage_events_time_idx ON usage_events(observed_at_ms);
CREATE INDEX usage_events_thread_idx ON usage_events(thread_id);
CREATE TABLE hourly_usage(
  hour_start_ms INTEGER NOT NULL, model TEXT NOT NULL, plan TEXT NOT NULL,
  uncached_input_tokens INTEGER NOT NULL, cached_input_tokens INTEGER NOT NULL,
  visible_output_tokens INTEGER NOT NULL, reasoning_tokens INTEGER NOT NULL,
  total_tokens INTEGER NOT NULL, PRIMARY KEY(hour_start_ms, model, plan)
);
CREATE TABLE quota_snapshots(
  fingerprint TEXT PRIMARY KEY, observed_at_ms INTEGER NOT NULL, thread_id TEXT NOT NULL,
  kind TEXT NOT NULL, window_minutes INTEGER NOT NULL, remaining REAL NOT NULL,
  resets_at_ms INTEGER, plan TEXT NOT NULL, plan_raw TEXT, plan_is_inferred INTEGER NOT NULL,
  source_kind TEXT NOT NULL
);
CREATE INDEX quota_latest_idx ON quota_snapshots(kind, observed_at_ms DESC);
CREATE TABLE session_state_events(
  fingerprint TEXT PRIMARY KEY, thread_id TEXT NOT NULL, turn_id TEXT,
  observed_at_ms INTEGER NOT NULL, kind TEXT NOT NULL,
  source_file_id TEXT NOT NULL, source_offset INTEGER NOT NULL
);
CREATE TABLE sessions(
  thread_id TEXT PRIMARY KEY, source_kind TEXT NOT NULL, created_at_ms INTEGER,
  updated_at_ms INTEGER, activity_state TEXT NOT NULL, archive_state TEXT NOT NULL,
  child_edge_status TEXT, active_turn_id TEXT, last_activity_at_ms INTEGER,
  last_event_key TEXT, last_model TEXT, last_plan TEXT, source_file_id TEXT
);
CREATE TABLE source_status(
  source_kind TEXT PRIMARY KEY, state TEXT NOT NULL, detail TEXT,
  last_success_at_ms INTEGER, processed_file_count INTEGER NOT NULL DEFAULT 0
);
```

- [ ] **Step 4: Implement atomic batch insertion and aggregation**

Define `StoredUsageEvent`, `StoredQuotaEvent`, `StoredSessionStateEvent`, `StoredSession`, `FileCheckpoint`, `ThreadCheckpoint`, and `ImportBatch` as `Sendable` structs. `UsageStore.commit` runs one transaction: `INSERT OR IGNORE` events, updates hourly totals only when the wrapper's `changes` value equals 1, upserts sessions/checkpoints, then upserts the source file offset last. Provide query helpers used by tests and the later query service.

- [ ] **Step 5: Run store tests and the existing test suite**

Expected: store tests pass; existing formatter and snapshot tests remain green.

- [ ] **Step 6: Commit storage slice**

```bash
git add SpendScope.xcodeproj/project.pbxproj Sources/SpendScope/Data/Storage/SQLiteDatabase.swift Sources/SpendScope/Data/Storage/UsageStore.swift Tests/SpendScopeTests/UsageStoreTests.swift
git commit -m "feat(data): persist normalized Codex usage"
```

### Task 4: Source Discovery and Incremental JSONL Reader

**Files:**
- Create: `Sources/SpendScope/Data/Codex/CodexSourceDiscovery.swift`
- Create: `Sources/SpendScope/Data/Codex/IncrementalJSONLReader.swift`
- Create: `Tests/SpendScopeTests/IncrementalJSONLReaderTests.swift`
- Modify: `SpendScope.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `CodexSourceDiscovery.discover(rootURL:) throws -> CodexSourceInventory`
- Produces: `IncrementalJSONLReader.read(file:fromOffset:) throws -> JSONLReadBatch`
- Produces: `CodexThreadIndexReader.read(databaseURL:) throws -> [ThreadIndexRecord]`

- [ ] **Step 1: Write failing partial-line and archive identity tests**

```swift
final class IncrementalJSONLReaderTests: XCTestCase {
    func testCommitsOnlyCompleteLinesAndContinuesAfterAppend() throws {
        let url = try temporaryFile(contents: "{\"type\":\"one\"}\n{\"type\":\"two")
        let reader = IncrementalJSONLReader(chunkSize: 8)

        let first = try reader.read(file: url, fromOffset: 0)
        XCTAssertEqual(first.lines.map { String(decoding: $0.data, as: UTF8.self) }, ["{\"type\":\"one\"}"])
        XCTAssertEqual(first.committedOffset, 15)

        try append("\"}\n", to: url)
        let second = try reader.read(file: url, fromOffset: first.committedOffset)
        XCTAssertEqual(second.lines.map { String(decoding: $0.data, as: UTF8.self) }, ["{\"type\":\"two\"}"])
    }

    func testDiscoveryUsesDeviceAndInodeWhenFileMovesToArchive() throws {
        let root = try makeCodexRootWithOneSession()
        let first = try CodexSourceDiscovery().discover(rootURL: root).rollouts[0]
        let archived = root.appending(path: "archived_sessions/rollout.jsonl")
        try FileManager.default.createDirectory(at: archived.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: first.url, to: archived)
        let second = try CodexSourceDiscovery().discover(rootURL: root).rollouts[0]

        XCTAssertEqual(first.fileID, second.fileID)
        XCTAssertNotEqual(first.url, second.url)
    }
}
```

- [ ] **Step 2: Run reader tests and verify failures**

Expected: missing discovery and reader symbols.

- [ ] **Step 3: Implement streaming line reads and file identity**

`IncrementalJSONLReader` uses `FileHandle.seek(toOffset:)` and `read(upToCount:)`, carries bytes after the final newline without emitting them, returns each line with its ending byte offset, and reports truncation when file size is below the requested offset. It must never call `Data(contentsOf:)` for a rollout.

`CodexSourceDiscovery` scans `sessions` recursively and `archived_sessions` directly for `*.jsonl`, reads device/inode using `FileManager.attributesOfItem`, and builds `fileID = "<device>:<inode>"`. It merges optional rows from the newest supported `state_*.sqlite` file by thread ID and rollout path.

`CodexThreadIndexReader` opens Codex SQLite with `SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX`, applies a 100 ms busy timeout, reads only id, rollout_path, source, model, timestamps, archived and thread_spawn_edges.status, and closes immediately. Discovery catches index errors and keeps filesystem results with a degraded source status.

- [ ] **Step 4: Register files and run reader tests**

Expected: both tests pass, including an 8-byte chunk boundary.

- [ ] **Step 5: Commit discovery slice**

```bash
git add SpendScope.xcodeproj/project.pbxproj Sources/SpendScope/Data/Codex/CodexSourceDiscovery.swift Sources/SpendScope/Data/Codex/IncrementalJSONLReader.swift Tests/SpendScopeTests/IncrementalJSONLReaderTests.swift
git commit -m "feat(data): discover and incrementally read rollouts"
```

### Task 5: Idempotent Codex Importer

**Files:**
- Create: `Sources/SpendScope/Data/Codex/CodexImporter.swift`
- Create: `Tests/SpendScopeTests/CodexImporterTests.swift`
- Modify: `SpendScope.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: decoder, normalizers, discovery, reader and `UsageStore`
- Produces: `actor CodexImporter`
- Produces: `CodexImporter.refresh(scope:) async -> ImportResult`
- Produces: `ImportScope.foreground` for current-day/latest files and `ImportScope.history` for remaining files

- [ ] **Step 1: Write failing end-to-end import tests**

```swift
final class CodexImporterTests: XCTestCase {
    func testImportsUsageQuotaAndSessionOnceAcrossRefreshes() async throws {
        let fixture = try CodexFixture.make(
            events: [.sessionDesktop, .turn(model: "gpt-5.6-sol"), .started, .token(input: 1_000, cached: 600, output: 100, reasoning: 40, plan: "plus"), .completed]
        )
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)

        _ = await importer.refresh(scope: .history)
        _ = await importer.refresh(scope: .history)

        XCTAssertEqual(try store.totalUsage(), 1_100)
        XCTAssertEqual(try store.latestQuotas().map(\.kind), [.fiveHour, .weekly])
        XCTAssertEqual(try store.sessions().first?.activity, .completed)
        XCTAssertEqual(try store.usageEventCount(), 1)
    }

    func testAppendAddsOnlyPositiveDeltaAndArchiveMoveDoesNotDuplicate() async throws {
        let fixture = try CodexFixture.make(events: [.sessionCLI, .turn(model: "gpt-5.5"), .token(input: 1_000, cached: 500, output: 100, reasoning: 20, plan: nil)])
        let store = try UsageStore(databaseURL: fixture.databaseURL)
        let importer = CodexImporter(rootURL: fixture.codexRoot, store: store)
        _ = await importer.refresh(scope: .history)

        try fixture.append(.token(input: 1_500, cached: 700, output: 160, reasoning: 30, plan: nil))
        _ = await importer.refresh(scope: .history)
        try fixture.archiveRollout()
        _ = await importer.refresh(scope: .history)

        XCTAssertEqual(try store.totalUsage(), 1_660)
        XCTAssertEqual(try store.sessions().first?.archive, .archived)
        XCTAssertEqual(try store.usageEventCount(), 2)
    }
}
```

- [ ] **Step 2: Run importer tests and verify failure**

Expected: build fails because `CodexImporter` and fixture helpers do not exist.

- [ ] **Step 3: Implement actor-owned import context and stable fingerprints**

`CodexImporter` owns one refresh at a time. For every rollout it loads file and thread checkpoints, reads complete new lines, tracks session metadata/current model/current plan, and creates usage, quota and state records.

Use CryptoKit SHA-256 fingerprints over canonical pipe-delimited UTF-8 strings:

```text
usage|threadID|observedAtMs|input|cached|output|reasoning
quota|threadID|observedAtMs|windowMinutes|usedPercent|resetsAt
state|threadID|observedAtMs|kind|turnID
```

Use the Token event timestamp for usage. Resolve model from the nearest turn context, then thread index model, then `Unknown Model`. Commit a file batch only after every complete line in that batch decodes; malformed JSON pauses that file at the malformed line and records an error without advancing beyond it.

`.foreground` imports files updated during the current local day plus the newest quota candidate, ordered by descending update time. `.history` imports every remaining file in the background. Both scopes use identical checkpoints and idempotency rules, so foreground files are skipped cheaply during history backfill.

For source classification, session metadata wins over thread index. Apply explicit archived and child-edge facts from the index after lifecycle reduction. A file in archived_sessions sets archive state even when the index is unavailable.

- [ ] **Step 4: Add anonymous fixture builder and make importer tests pass**

Keep fixture JSON lines in `CodexImporterTests.swift`; they may contain only synthetic IDs, models and counters. Register production and test files, run importer tests twice, and confirm the second refresh leaves counts unchanged.

- [ ] **Step 5: Run the complete test suite**

Expected: all decoder, reducer, store, reader, importer and existing UI model tests pass.

- [ ] **Step 6: Commit importer slice**

```bash
git add SpendScope.xcodeproj/project.pbxproj Sources/SpendScope/Data/Codex/CodexImporter.swift Tests/SpendScopeTests/CodexImporterTests.swift
git commit -m "feat(data): import Codex rollouts idempotently"
```

### Task 6: Dashboard Queries from Real Data

**Files:**
- Create: `Sources/SpendScope/Data/Dashboard/DashboardQueryService.swift`
- Create: `Sources/SpendScope/Data/Dashboard/SessionQueryService.swift`
- Create: `Tests/SpendScopeTests/DashboardQueryServiceTests.swift`
- Create: `Tests/SpendScopeTests/SessionQueryServiceTests.swift`
- Modify: `Sources/SpendScope/Models/DashboardSnapshot.swift`
- Modify: `SpendScope.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `UsageStore` aggregate and latest-quota queries
- Produces: `DashboardQueryService.snapshot(now:calendar:) throws -> DashboardSnapshot`
- Produces: `SessionQueryService.sessions(filter:now:) throws -> [SessionSummary]`
- Produces: `DashboardSnapshot.empty(updatedText:)`

- [ ] **Step 1: Write failing fixed-clock query tests**

```swift
final class DashboardQueryServiceTests: XCTestCase {
    func testBuildsLocalDayPeriodsAndQuotaWindows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date(timeIntervalSince1970: 1_784_044_800)
        let store = try seededStore(calendar: calendar, now: now)
        let snapshot = try DashboardQueryService(store: store).snapshot(now: now, calendar: calendar)

        XCTAssertEqual(snapshot.periods.map(\.title), ["今日", "7 日", "30 日", "累计"])
        XCTAssertEqual(snapshot.breakdown.total, snapshot.todayTokens)
        XCTAssertEqual(snapshot.visibleQuotas.map(\.id), ["5h", "7d"])
        XCTAssertEqual(snapshot.planName, "Plus")
    }

    func testReturnsFourZeroPeriodsWhenStoreHasNoUsage() throws {
        let snapshot = try DashboardQueryService(store: try makeStore()).snapshot(now: Date(), calendar: .current)
        XCTAssertEqual(snapshot.periods.count, 4)
        XCTAssertTrue(snapshot.periods.allSatisfy { $0.total == 0 })
        XCTAssertTrue(snapshot.quotas.isEmpty)
    }
}
```

```swift
final class SessionQueryServiceTests: XCTestCase {
    func testFiltersByDisplayStateAndMarksOldRunningObservationStale() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try seededSessionStore(
            activity: .running, archive: .active,
            lastRecordAtMilliseconds: 600_000
        )
        let rows = try SessionQueryService(store: store).sessions(
            filter: .init(displayStates: [.running]), now: now
        )

        XCTAssertEqual(rows.map(\.displayState), [.running])
        XCTAssertEqual(rows.map(\.freshness), [.stale])
    }
}
```

- [ ] **Step 2: Run query tests and verify missing service failure**

Expected: build fails because `DashboardQueryService` and `SessionQueryService` do not exist.

- [ ] **Step 3: Implement period, trend, model and quota queries**

Compute day boundaries with `calendar.startOfDay(for:)` and `calendar.date(byAdding:.day,value:)`. Query raw `usage_events` for exact UTC ranges, group daily trend by local date in Swift, and calculate model shares for the default seven-day range. Convert Int64 to Int with saturation at `Int.max`.

Map quota observations to UI as follows:

```swift
QuotaSnapshot(
    id: kind == .fiveHour ? "5h" : "7d",
    title: kind == .fiveHour ? "5 小时" : "7 天",
    remaining: remaining,
    resetText: QuotaResetFormatter.string(kind: kind, resetsAtMilliseconds: resetsAt)
)
```

Format 5-hour reset as local `HH:mm`; format weekly reset as `yyyy-MM-dd HH:mm`. When reset time has passed without a newer observation, omit that quota from `visibleQuotas` and expose a source issue for the store rather than showing 100%.

Add `DashboardSnapshot.empty(updatedText:)` with four zero periods and empty quotas/models/trend. Replace direct `periods[0...3]` accessors with ID-based lookup plus zero fallback so malformed or loading data cannot crash the menu bar.

Implement `SessionFilter`, `SessionSummary`, `SessionFreshness` and `SessionQueryService`. Query sessions by orthogonal activity/archive/source/model/plan facts, derive display priority in Swift, and mark a running session stale when its source file `last_record_at_ms` is more than 5 minutes before `now`. `SessionSummary` exposes a short thread ID, times, source, model, plan, state, freshness and Token total; it has no title/message fields.

- [ ] **Step 4: Register files and run query plus existing snapshot tests**

Expected: query tests pass and existing preview tests remain unchanged.

- [ ] **Step 5: Commit query slice**

```bash
git add SpendScope.xcodeproj/project.pbxproj Sources/SpendScope/Data/Dashboard/DashboardQueryService.swift Sources/SpendScope/Data/Dashboard/SessionQueryService.swift Sources/SpendScope/Models/DashboardSnapshot.swift Tests/SpendScopeTests/DashboardQueryServiceTests.swift Tests/SpendScopeTests/SessionQueryServiceTests.swift
git commit -m "feat(data): build dashboard snapshots from usage"
```

### Task 7: Shared DashboardStore and Direct SwiftUI Integration

**Files:**
- Create: `Sources/SpendScope/App/DashboardStore.swift`
- Create: `Tests/SpendScopeTests/DashboardStoreTests.swift`
- Modify: `Sources/SpendScope/App/SpendScopeApp.swift`
- Modify: `Sources/SpendScope/Features/Dashboard/DashboardView.swift`
- Modify: `Sources/SpendScope/Features/MenuBar/MenuBarPopoverView.swift`
- Modify: `Sources/SpendScope/Features/Settings/SettingsView.swift`
- Modify: `SpendScope.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CodexImporter` and `DashboardQueryService`
- Produces: `@MainActor @Observable final class DashboardStore`
- Produces: `DashboardLoadState` and `SourceSummary`

- [ ] **Step 1: Write failing store state-transition tests**

```swift
@MainActor
final class DashboardStoreTests: XCTestCase {
    func testRefreshPublishesRealSnapshotAndRunsOnlyOnceConcurrently() async {
        let client = FakeDashboardDataClient(result: .loaded(.preview, .fixture))
        let store = DashboardStore(client: client, refreshInterval: .seconds(60))

        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)

        guard case let .loaded(snapshot, _) = store.state else {
            return XCTFail("Expected loaded state")
        }
        XCTAssertEqual(snapshot.todayTokens, DashboardSnapshot.preview.todayTokens)
        let refreshCount = await client.refreshCount
        XCTAssertEqual(refreshCount, 1)
    }

    func testNoCodexDataPublishesEmptyInsteadOfPreview() async {
        let store = DashboardStore(client: FakeDashboardDataClient(result: .empty(.fixture)))
        await store.refresh()
        guard case .empty = store.state else { return XCTFail("Expected empty state") }
    }
}
```

- [ ] **Step 2: Run store tests and verify missing store/client failures**

Expected: build fails because the observable store has not been created.

- [ ] **Step 3: Implement the observable store and live client**

Define:

```swift
enum DashboardLoadState: Sendable {
    case loading
    case loaded(DashboardSnapshot, SourceSummary)
    case empty(SourceSummary)
    case stale(DashboardSnapshot, SourceSummary, String)
    case failed(String)
    case unsupported(String)
}

enum SourceHealth: String, Sendable {
    case connected, missing, degraded, unsupported
}

struct SourceSummary: Sendable {
    let cli: SourceHealth
    let desktop: SourceHealth
    let index: SourceHealth
    let lastSuccessfulRefresh: Date?
}

enum DashboardDataResult: Sendable {
    case loaded(DashboardSnapshot, SourceSummary)
    case empty(SourceSummary)
    case stale(DashboardSnapshot, SourceSummary, String)
    case unsupported(String)
}

protocol DashboardDataClient: Sendable {
    func loadCached() async throws -> DashboardDataResult
    func refresh() async throws -> DashboardDataResult
    func backfillHistory() async throws -> DashboardDataResult
}

@MainActor @Observable
final class DashboardStore {
    private(set) var state: DashboardLoadState = .loading
    private var inFlightRefresh: Task<DashboardDataResult, Error>?
    private var automaticRefreshTask: Task<Void, Never>?
    func start() async
    func refresh() async
}
```

Test code defines the fixture explicitly:

```swift
extension SourceSummary {
    static let fixture = SourceSummary(
        cli: .connected, desktop: .connected, index: .connected,
        lastSuccessfulRefresh: Date(timeIntervalSince1970: 1)
    )
}

actor FakeDashboardDataClient: DashboardDataClient {
    let result: DashboardDataResult
    private(set) var refreshCount = 0

    init(result: DashboardDataResult) { self.result = result }
    func loadCached() async throws -> DashboardDataResult { result }
    func refresh() async throws -> DashboardDataResult {
        refreshCount += 1
        return result
    }
    func backfillHistory() async throws -> DashboardDataResult { result }
}
```

The live client creates `~/Library/Application Support/SpendScope/SpendScope.sqlite`; `loadCached` only queries SQLite, `refresh` invokes `.foreground`, and `backfillHistory` invokes `.history` before querying again. `DashboardStore.refresh` coalesces concurrent calls into one task. `start` loads the previous SQLite snapshot, publishes the foreground result, starts one background history pass, then owns a cancellable loop that sleeps 60 seconds between foreground refreshes.

- [ ] **Step 4: Replace production preview injection with one shared store**

In `SpendScopeApp`, create `@State private var store = DashboardStore.live()` and pass it to the menu bar, dashboard and settings. The menu label uses the latest real snapshot label or `SpendScope` while loading.

`DashboardView` keeps the existing layout for loaded/stale snapshots and uses `ContentUnavailableView` for loading, empty, failed and unsupported states. `MenuBarPopoverView` uses the same state, connects the refresh button to `await store.refresh()`, disables it while refreshing, and shows `--` when quota is missing. `SettingsView` replaces “待接入” with source summary values such as “已连接”, “未检测到”, “格式不兼容” and the last refresh time.

Never substitute `DashboardSnapshot.preview` in a production state branch.

- [ ] **Step 5: Run store tests and complete Xcode suite**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SpendScope.xcodeproj -scheme SpendScope -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/SpendScope-DataCapture test -quiet
```

Expected: all tests pass.

- [ ] **Step 6: Build the app**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SpendScope.xcodeproj -scheme SpendScope -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/SpendScope-DataCapture build -quiet
```

Expected: build exits 0 without Swift concurrency warnings from the new data pipeline.

- [ ] **Step 7: Commit UI integration slice**

```bash
git add SpendScope.xcodeproj/project.pbxproj Sources/SpendScope/App/DashboardStore.swift Sources/SpendScope/App/SpendScopeApp.swift Sources/SpendScope/Features/Dashboard/DashboardView.swift Sources/SpendScope/Features/MenuBar/MenuBarPopoverView.swift Sources/SpendScope/Features/Settings/SettingsView.swift Tests/SpendScopeTests/DashboardStoreTests.swift
git commit -m "feat: connect dashboard to local Codex data"
```

### Task 8: Real-Data Verification, Privacy Audit, and Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-07-14-codex-data-capture-design.md` only if verification reveals an implementation-level clarification

**Interfaces:**
- Consumes: completed importer and UI integration
- Produces: documented local verification and clean release-ready build

- [ ] **Step 1: Run a read-only import against the developer Codex root**

Launch the Debug app from Xcode or `./script/build_and_run.sh --verify`. Confirm:

- menu label no longer shows preview 85%/84% unless those are real current values;
- today, 7-day, 30-day and all-time totals load;
- available 5-hour/7-day windows match local token_count observations;
- manual refresh does not double totals;
- already archived Codex threads do not duplicate active-history totals;
- Codex remains usable during import.

- [ ] **Step 2: Inspect the SpendScope database schema and payload boundaries**

Run read-only schema and column inspection against `~/Library/Application Support/SpendScope/SpendScope.sqlite`. Verify no table or column stores prompt, message, title, response, summary, tool input, file content, credential or auth data. Do not print Codex source rows or conversation content.

- [ ] **Step 3: Verify incremental performance**

Record first import duration and then trigger a no-change refresh. The second refresh must not reread historical file contents and should complete using file metadata/checkpoints. Use Instruments or signposts only if the second refresh visibly blocks UI; no telemetry leaves the machine.

- [ ] **Step 4: Update README status and architecture**

Replace “真实数据尚未接入” with a concise description of supported CLI/Desktop rollout capture, local SQLite location, 60-second refresh, privacy boundary, and current limitations. Keep costs and notifications marked as not implemented.

- [ ] **Step 5: Run final tests, build, and diff checks**

```bash
git diff --check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SpendScope.xcodeproj -scheme SpendScope -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/SpendScope-DataCapture test -quiet
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SpendScope.xcodeproj -scheme SpendScope -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/SpendScope-DataCapture-Release build -quiet
```

Expected: diff check, Debug tests and Release build all pass.

- [ ] **Step 6: Commit verification and docs**

```bash
git add README.md docs/superpowers/specs/2026-07-14-codex-data-capture-design.md
git commit -m "docs: document local Codex data capture"
```
