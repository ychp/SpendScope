import Foundation

struct StoredUsageEvent: Sendable {
    let fingerprint: String
    let observedAtMilliseconds: Int64
    let threadID: String
    let sourceKind: CodexSourceKind
    let model: String
    let plan: PlanResolution
    let usage: TokenUsageDelta
    let sourceFileID: String
    let sourceOffset: Int64
}

struct StoredQuotaEvent: Sendable {
    let fingerprint: String
    let threadID: String
    let observation: QuotaObservation
    let sourceKind: CodexSourceKind
}

struct StoredSessionStateEvent: Sendable {
    let fingerprint: String
    let threadID: String
    let turnID: String?
    let observedAtMilliseconds: Int64
    let kind: SessionLifecycleKind
    let sourceFileID: String
    let sourceOffset: Int64
}

struct StoredSession: Sendable {
    let threadID: String
    let sourceKind: CodexSourceKind
    let createdAtMilliseconds: Int64?
    let updatedAtMilliseconds: Int64?
    let state: SessionStateSnapshot
    let lastModel: String?
    let lastPlan: PlanKind?
    let sourceFileID: String?

    var activity: SessionActivityState { state.activity }
    var archive: SessionArchiveState { state.archive }
    var childEdgeStatus: String? { state.childEdgeStatus }
    var activeTurnID: String? { state.activeTurnID }
}

struct FileCheckpoint: Sendable {
    let fileID: String
    let deviceID: Int64
    let inode: Int64
    let path: String
    let fileSize: Int64
    let committedOffset: Int64
    let generation: Int64
    let lastRecordAtMilliseconds: Int64?
    let lastSuccessAtMilliseconds: Int64?
    let formatStatus: String
    let lastError: String?
}

struct ThreadCheckpoint: Sendable {
    let threadID: String
    let currentModel: String?
    let counters: TokenCounters?
    let counterSegment: Int64
    let lastTokenAtMilliseconds: Int64?
}

struct ImportBatch: Sendable {
    let file: FileCheckpoint
    let usageEvents: [StoredUsageEvent]
    let quotaEvents: [StoredQuotaEvent]
    let stateEvents: [StoredSessionStateEvent]
    let sessions: [StoredSession]
    let threadCheckpoints: [ThreadCheckpoint]
}

struct StoredHourlyUsage: Equatable, Sendable {
    let hourStartMilliseconds: Int64
    let model: String
    let plan: PlanKind
    let uncachedInputTokens: Int64
    let cachedInputTokens: Int64
    let visibleOutputTokens: Int64
    let reasoningTokens: Int64
    let totalTokens: Int64
}

final class UsageStore {
    private let database: SQLiteDatabase

    init(databaseURL: URL) throws {
        database = try SQLiteDatabase(url: databaseURL)
        try migrate()
    }

    func commit(_ batch: ImportBatch) throws {
        try database.inTransaction {
            for event in batch.usageEvents {
                let inserted = try insertUsageEvent(event)
                if inserted == 1 {
                    try addToHourlyUsage(event)
                }
            }

            for event in batch.quotaEvents {
                try insertQuotaEvent(event)
            }
            for event in batch.stateEvents {
                try insertSessionStateEvent(event)
            }
            for session in batch.sessions {
                try upsertSession(session)
            }
            for checkpoint in batch.threadCheckpoints {
                try upsertThreadCheckpoint(checkpoint)
            }

            try upsertFileCheckpoint(batch.file)
        }
    }

    func totalUsage() throws -> Int64 {
        let rows = try database.query(sql: "SELECT COALESCE(SUM(total_tokens), 0) AS total FROM usage_events")
        return rows.first?["total"]?.int64 ?? 0
    }

    func usageEventCount() throws -> Int64 {
        try count(table: "usage_events")
    }

    func quotaEventCount() throws -> Int64 {
        try count(table: "quota_snapshots")
    }

    func sessionStateEventCount() throws -> Int64 {
        try count(table: "session_state_events")
    }

    func fileCheckpoint(fileID: String) throws -> FileCheckpoint? {
        let rows = try database.query(
            sql: """
            SELECT file_id, device_id, inode, path, file_size, committed_offset, generation,
                   last_record_at_ms, last_success_at_ms, format_status, last_error
            FROM source_files WHERE file_id = ?
            """,
            bindings: [.text(fileID)]
        )
        guard let row = rows.first else { return nil }
        return FileCheckpoint(
            fileID: row.requiredString("file_id"),
            deviceID: row.requiredInt64("device_id"),
            inode: row.requiredInt64("inode"),
            path: row.requiredString("path"),
            fileSize: row.requiredInt64("file_size"),
            committedOffset: row.requiredInt64("committed_offset"),
            generation: row.requiredInt64("generation"),
            lastRecordAtMilliseconds: row.optionalInt64("last_record_at_ms"),
            lastSuccessAtMilliseconds: row.optionalInt64("last_success_at_ms"),
            formatStatus: row.requiredString("format_status"),
            lastError: row.optionalString("last_error")
        )
    }

    func threadCheckpoint(threadID: String) throws -> ThreadCheckpoint? {
        let rows = try database.query(
            sql: "SELECT * FROM thread_checkpoints WHERE thread_id = ?",
            bindings: [.text(threadID)]
        )
        guard let row = rows.first else { return nil }
        let counters: TokenCounters?
        if let input = row.optionalInt64("input_tokens"),
           let cached = row.optionalInt64("cached_input_tokens"),
           let output = row.optionalInt64("output_tokens"),
           let reasoning = row.optionalInt64("reasoning_tokens") {
            counters = TokenCounters(input: input, cachedInput: cached, output: output, reasoning: reasoning)
        } else {
            counters = nil
        }
        return ThreadCheckpoint(
            threadID: row.requiredString("thread_id"),
            currentModel: row.optionalString("current_model"),
            counters: counters,
            counterSegment: row.requiredInt64("counter_segment"),
            lastTokenAtMilliseconds: row.optionalInt64("last_token_at_ms")
        )
    }

    func hourlyUsage() throws -> [StoredHourlyUsage] {
        try database.query(
            sql: "SELECT * FROM hourly_usage ORDER BY hour_start_ms, model, plan"
        ).compactMap { row in
            guard let plan = PlanKind(rawValue: row.requiredString("plan")) else { return nil }
            return StoredHourlyUsage(
                hourStartMilliseconds: row.requiredInt64("hour_start_ms"),
                model: row.requiredString("model"),
                plan: plan,
                uncachedInputTokens: row.requiredInt64("uncached_input_tokens"),
                cachedInputTokens: row.requiredInt64("cached_input_tokens"),
                visibleOutputTokens: row.requiredInt64("visible_output_tokens"),
                reasoningTokens: row.requiredInt64("reasoning_tokens"),
                totalTokens: row.requiredInt64("total_tokens")
            )
        }
    }

    func sessions() throws -> [StoredSession] {
        try database.query(sql: "SELECT * FROM sessions ORDER BY thread_id").compactMap { row in
            guard let source = CodexSourceKind(rawValue: row.requiredString("source_kind")),
                  let activity = SessionActivityState(rawValue: row.requiredString("activity_state")),
                  let archive = SessionArchiveState(rawValue: row.requiredString("archive_state")) else {
                return nil
            }
            let threadID = row.requiredString("thread_id")
            return StoredSession(
                threadID: threadID,
                sourceKind: source,
                createdAtMilliseconds: row.optionalInt64("created_at_ms"),
                updatedAtMilliseconds: row.optionalInt64("updated_at_ms"),
                state: SessionStateSnapshot(
                    threadID: threadID,
                    activity: activity,
                    archive: archive,
                    childEdgeStatus: row.optionalString("child_edge_status"),
                    activeTurnID: row.optionalString("active_turn_id"),
                    lastActivityAtMilliseconds: row.optionalInt64("last_activity_at_ms"),
                    lastActivityEventKey: row.optionalString("last_event_key"),
                    archiveObservedAtMilliseconds: nil
                ),
                lastModel: row.optionalString("last_model"),
                lastPlan: row.optionalString("last_plan").flatMap(PlanKind.init(rawValue:)),
                sourceFileID: row.optionalString("source_file_id")
            )
        }
    }

    func schemaVersions() throws -> [Int64] {
        try database.query(sql: "SELECT version FROM schema_migrations ORDER BY version")
            .compactMap { $0["version"]?.int64 }
    }

    func schemaTables() throws -> [String] {
        try database.query(
            sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).compactMap { $0["name"]?.string }
    }

    func schemaColumns(table: String) throws -> [String] {
        guard table.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return [] }
        return try database.query(sql: "PRAGMA table_info(\(table))")
            .compactMap { $0["name"]?.string }
    }

    private func migrate() throws {
        try database.inTransaction {
            try database.execute(sql: "CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY)")
            let versions = try database.query(sql: "SELECT version FROM schema_migrations ORDER BY version")
                .compactMap { $0["version"]?.int64 }

            guard versions.last ?? 0 <= 1 else {
                throw UsageStoreError.unsupportedSchemaVersion(versions.last ?? 0)
            }
            guard !versions.contains(1) else { return }

            for statement in Self.versionOneStatements {
                try database.execute(sql: statement)
            }
            try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (1)")
        }
    }

    @discardableResult
    private func insertUsageEvent(_ event: StoredUsageEvent) throws -> Int32 {
        try database.execute(
            sql: """
            INSERT OR IGNORE INTO usage_events(
              fingerprint, observed_at_ms, thread_id, source_kind, model, plan, plan_raw,
              plan_is_inferred, uncached_input_tokens, cached_input_tokens,
              visible_output_tokens, reasoning_tokens, total_tokens, source_file_id, source_offset
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(event.fingerprint), .integer(event.observedAtMilliseconds), .text(event.threadID),
                .text(event.sourceKind.rawValue), .text(event.model), .text(event.plan.kind.rawValue),
                event.plan.rawValue.sqliteValue, .integer(event.plan.isInferred ? 1 : 0),
                .integer(event.usage.uncachedInput), .integer(event.usage.cachedInput),
                .integer(event.usage.visibleOutput), .integer(event.usage.reasoning),
                .integer(event.usage.total), .text(event.sourceFileID), .integer(event.sourceOffset)
            ]
        )
    }

    private func addToHourlyUsage(_ event: StoredUsageEvent) throws {
        let hourStart = event.observedAtMilliseconds - event.observedAtMilliseconds % 3_600_000
        try database.execute(
            sql: """
            INSERT INTO hourly_usage(
              hour_start_ms, model, plan, uncached_input_tokens, cached_input_tokens,
              visible_output_tokens, reasoning_tokens, total_tokens
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(hour_start_ms, model, plan) DO UPDATE SET
              uncached_input_tokens = uncached_input_tokens + excluded.uncached_input_tokens,
              cached_input_tokens = cached_input_tokens + excluded.cached_input_tokens,
              visible_output_tokens = visible_output_tokens + excluded.visible_output_tokens,
              reasoning_tokens = reasoning_tokens + excluded.reasoning_tokens,
              total_tokens = total_tokens + excluded.total_tokens
            """,
            bindings: [
                .integer(hourStart), .text(event.model), .text(event.plan.kind.rawValue),
                .integer(event.usage.uncachedInput), .integer(event.usage.cachedInput),
                .integer(event.usage.visibleOutput), .integer(event.usage.reasoning),
                .integer(event.usage.total)
            ]
        )
    }

    private func insertQuotaEvent(_ event: StoredQuotaEvent) throws {
        let observation = event.observation
        try database.execute(
            sql: """
            INSERT OR IGNORE INTO quota_snapshots(
              fingerprint, observed_at_ms, thread_id, kind, window_minutes, remaining,
              resets_at_ms, plan, plan_raw, plan_is_inferred, source_kind
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(event.fingerprint), .integer(observation.observedAtMilliseconds),
                .text(event.threadID), .text(observation.kind.rawValue),
                .integer(Int64(observation.windowMinutes)), .real(observation.remaining),
                observation.resetsAtMilliseconds.sqliteValue, .text(observation.plan.kind.rawValue),
                observation.plan.rawValue.sqliteValue, .integer(observation.plan.isInferred ? 1 : 0),
                .text(event.sourceKind.rawValue)
            ]
        )
    }

    private func insertSessionStateEvent(_ event: StoredSessionStateEvent) throws {
        try database.execute(
            sql: """
            INSERT OR IGNORE INTO session_state_events(
              fingerprint, thread_id, turn_id, observed_at_ms, kind, source_file_id, source_offset
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(event.fingerprint), .text(event.threadID), event.turnID.sqliteValue,
                .integer(event.observedAtMilliseconds), .text(event.kind.rawValue),
                .text(event.sourceFileID), .integer(event.sourceOffset)
            ]
        )
    }

    private func upsertSession(_ session: StoredSession) throws {
        try database.execute(
            sql: """
            INSERT INTO sessions(
              thread_id, source_kind, created_at_ms, updated_at_ms, activity_state, archive_state,
              child_edge_status, active_turn_id, last_activity_at_ms, last_event_key,
              last_model, last_plan, source_file_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(thread_id) DO UPDATE SET
              source_kind = excluded.source_kind, created_at_ms = excluded.created_at_ms,
              updated_at_ms = excluded.updated_at_ms, activity_state = excluded.activity_state,
              archive_state = excluded.archive_state, child_edge_status = excluded.child_edge_status,
              active_turn_id = excluded.active_turn_id, last_activity_at_ms = excluded.last_activity_at_ms,
              last_event_key = excluded.last_event_key, last_model = excluded.last_model,
              last_plan = excluded.last_plan, source_file_id = excluded.source_file_id
            """,
            bindings: [
                .text(session.threadID), .text(session.sourceKind.rawValue),
                session.createdAtMilliseconds.sqliteValue, session.updatedAtMilliseconds.sqliteValue,
                .text(session.activity.rawValue), .text(session.archive.rawValue),
                session.childEdgeStatus.sqliteValue, session.activeTurnID.sqliteValue,
                session.state.lastActivityAtMilliseconds.sqliteValue,
                session.state.lastActivityEventKey.sqliteValue, session.lastModel.sqliteValue,
                (session.lastPlan?.rawValue).sqliteValue, session.sourceFileID.sqliteValue
            ]
        )
    }

    private func upsertThreadCheckpoint(_ checkpoint: ThreadCheckpoint) throws {
        try database.execute(
            sql: """
            INSERT INTO thread_checkpoints(
              thread_id, current_model, input_tokens, cached_input_tokens, output_tokens,
              reasoning_tokens, counter_segment, last_token_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(thread_id) DO UPDATE SET
              current_model = excluded.current_model, input_tokens = excluded.input_tokens,
              cached_input_tokens = excluded.cached_input_tokens, output_tokens = excluded.output_tokens,
              reasoning_tokens = excluded.reasoning_tokens, counter_segment = excluded.counter_segment,
              last_token_at_ms = excluded.last_token_at_ms
            """,
            bindings: [
                .text(checkpoint.threadID), checkpoint.currentModel.sqliteValue,
                (checkpoint.counters?.input).sqliteValue, (checkpoint.counters?.cachedInput).sqliteValue,
                (checkpoint.counters?.output).sqliteValue, (checkpoint.counters?.reasoning).sqliteValue,
                .integer(checkpoint.counterSegment), checkpoint.lastTokenAtMilliseconds.sqliteValue
            ]
        )
    }

    private func upsertFileCheckpoint(_ checkpoint: FileCheckpoint) throws {
        guard checkpoint.fileSize >= 0,
              checkpoint.committedOffset >= 0,
              checkpoint.committedOffset <= checkpoint.fileSize else {
            throw UsageStoreError.invalidFileCheckpoint(
                fileSize: checkpoint.fileSize,
                committedOffset: checkpoint.committedOffset
            )
        }
        try database.execute(
            sql: """
            INSERT INTO source_files(
              file_id, device_id, inode, path, file_size, committed_offset, generation,
              last_record_at_ms, last_success_at_ms, format_status, last_error
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_id) DO UPDATE SET
              device_id = excluded.device_id, inode = excluded.inode, path = excluded.path,
              file_size = excluded.file_size, committed_offset = excluded.committed_offset,
              generation = excluded.generation, last_record_at_ms = excluded.last_record_at_ms,
              last_success_at_ms = excluded.last_success_at_ms, format_status = excluded.format_status,
              last_error = excluded.last_error
            """,
            bindings: [
                .text(checkpoint.fileID), .integer(checkpoint.deviceID), .integer(checkpoint.inode),
                .text(checkpoint.path), .integer(checkpoint.fileSize), .integer(checkpoint.committedOffset),
                .integer(checkpoint.generation), checkpoint.lastRecordAtMilliseconds.sqliteValue,
                checkpoint.lastSuccessAtMilliseconds.sqliteValue, .text(checkpoint.formatStatus),
                checkpoint.lastError.sqliteValue
            ]
        )
    }

    private func count(table: String) throws -> Int64 {
        let rows = try database.query(sql: "SELECT COUNT(*) AS count FROM \(table)")
        return rows.first?["count"]?.int64 ?? 0
    }

    private static let versionOneStatements = [
        """
        CREATE TABLE source_files(
          file_id TEXT PRIMARY KEY, device_id INTEGER NOT NULL, inode INTEGER NOT NULL,
          path TEXT NOT NULL, file_size INTEGER NOT NULL DEFAULT 0,
          committed_offset INTEGER NOT NULL DEFAULT 0,
          generation INTEGER NOT NULL DEFAULT 0, last_record_at_ms INTEGER,
          last_success_at_ms INTEGER, format_status TEXT NOT NULL DEFAULT 'supported', last_error TEXT
        )
        """,
        """
        CREATE TABLE thread_checkpoints(
          thread_id TEXT PRIMARY KEY, current_model TEXT,
          input_tokens INTEGER, cached_input_tokens INTEGER, output_tokens INTEGER, reasoning_tokens INTEGER,
          counter_segment INTEGER NOT NULL DEFAULT 0, last_token_at_ms INTEGER
        )
        """,
        """
        CREATE TABLE usage_events(
          fingerprint TEXT PRIMARY KEY, observed_at_ms INTEGER NOT NULL, thread_id TEXT NOT NULL,
          source_kind TEXT NOT NULL, model TEXT NOT NULL, plan TEXT NOT NULL, plan_raw TEXT,
          plan_is_inferred INTEGER NOT NULL, uncached_input_tokens INTEGER NOT NULL,
          cached_input_tokens INTEGER NOT NULL, visible_output_tokens INTEGER NOT NULL,
          reasoning_tokens INTEGER NOT NULL, total_tokens INTEGER NOT NULL,
          source_file_id TEXT NOT NULL, source_offset INTEGER NOT NULL
        )
        """,
        "CREATE INDEX usage_events_time_idx ON usage_events(observed_at_ms)",
        "CREATE INDEX usage_events_thread_idx ON usage_events(thread_id)",
        """
        CREATE TABLE hourly_usage(
          hour_start_ms INTEGER NOT NULL, model TEXT NOT NULL, plan TEXT NOT NULL,
          uncached_input_tokens INTEGER NOT NULL, cached_input_tokens INTEGER NOT NULL,
          visible_output_tokens INTEGER NOT NULL, reasoning_tokens INTEGER NOT NULL,
          total_tokens INTEGER NOT NULL, PRIMARY KEY(hour_start_ms, model, plan)
        )
        """,
        """
        CREATE TABLE quota_snapshots(
          fingerprint TEXT PRIMARY KEY, observed_at_ms INTEGER NOT NULL, thread_id TEXT NOT NULL,
          kind TEXT NOT NULL, window_minutes INTEGER NOT NULL, remaining REAL NOT NULL,
          resets_at_ms INTEGER, plan TEXT NOT NULL, plan_raw TEXT, plan_is_inferred INTEGER NOT NULL,
          source_kind TEXT NOT NULL
        )
        """,
        "CREATE INDEX quota_latest_idx ON quota_snapshots(kind, observed_at_ms DESC)",
        """
        CREATE TABLE session_state_events(
          fingerprint TEXT PRIMARY KEY, thread_id TEXT NOT NULL, turn_id TEXT,
          observed_at_ms INTEGER NOT NULL, kind TEXT NOT NULL,
          source_file_id TEXT NOT NULL, source_offset INTEGER NOT NULL
        )
        """,
        """
        CREATE TABLE sessions(
          thread_id TEXT PRIMARY KEY, source_kind TEXT NOT NULL, created_at_ms INTEGER,
          updated_at_ms INTEGER, activity_state TEXT NOT NULL, archive_state TEXT NOT NULL,
          child_edge_status TEXT, active_turn_id TEXT, last_activity_at_ms INTEGER,
          last_event_key TEXT, last_model TEXT, last_plan TEXT, source_file_id TEXT
        )
        """,
        """
        CREATE TABLE source_status(
          source_kind TEXT PRIMARY KEY, state TEXT NOT NULL, detail TEXT,
          last_success_at_ms INTEGER, processed_file_count INTEGER NOT NULL DEFAULT 0
        )
        """
    ]
}

enum UsageStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int64)
    case invalidFileCheckpoint(fileSize: Int64, committedOffset: Int64)
}

private extension Optional where Wrapped == String {
    var sqliteValue: SQLiteValue {
        map(SQLiteValue.text) ?? .null
    }
}

private extension Optional where Wrapped == Int64 {
    var sqliteValue: SQLiteValue {
        map(SQLiteValue.integer) ?? .null
    }
}

private extension Int64 {
    var sqliteValue: SQLiteValue { .integer(self) }
}

private extension Dictionary where Key == String, Value == SQLiteValue {
    func requiredInt64(_ key: String) -> Int64 { self[key]?.int64 ?? 0 }
    func optionalInt64(_ key: String) -> Int64? { self[key]?.int64 }
    func requiredString(_ key: String) -> String { self[key]?.string ?? "" }
    func optionalString(_ key: String) -> String? { self[key]?.string }
}
