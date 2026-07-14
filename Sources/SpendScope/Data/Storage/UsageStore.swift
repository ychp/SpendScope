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
    let threadID: String?
    let lastRecordAtMilliseconds: Int64?
    let lastSuccessAtMilliseconds: Int64?
    let formatStatus: String
    let lastError: String?
}

struct ThreadCheckpoint: Sendable {
    let threadID: String
    let currentModel: String?
    let currentPlan: PlanResolution?
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

struct StoredUsageQueryRow: Sendable {
    let fingerprint: String
    let observedAtMilliseconds: Int64
    let threadID: String
    let model: String
    let plan: PlanResolution
    let uncachedInputTokens: Int64
    let cachedInputTokens: Int64
    let visibleOutputTokens: Int64
    let reasoningTokens: Int64
    let totalTokens: Int64
}

struct StoredSessionQueryRow: Sendable {
    let session: StoredSession
    let sourceLastRecordAtMilliseconds: Int64?
    let totalTokens: Int64
}

final class UsageStore: @unchecked Sendable {
    private let database: SQLiteDatabase

    init(databaseURL: URL) throws {
        database = try SQLiteDatabase(url: databaseURL)
        try migrate()
    }

    func commit(_ batch: ImportBatch) throws {
        try database.inTransaction {
            for event in batch.usageEvents {
                let total = try validatedTotal(for: event.usage)
                let inserted = try insertUsageEvent(event, total: total)
                if inserted == 1 {
                    try addToHourlyUsage(event, total: total)
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
        let rows = try database.query(sql: "SELECT total_tokens FROM usage_events ORDER BY fingerprint")
        var total: Int64 = 0
        for values in rows {
            let row = SQLiteRow(table: "usage_events", values: values)
            total = try checkedAdd(
                total,
                row.requiredInt64("total_tokens"),
                context: "usage_events.total_tokens"
            )
        }
        return total
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
                   thread_id, last_record_at_ms, last_success_at_ms, format_status, last_error
            FROM source_files WHERE file_id = ?
            """,
            bindings: [.text(fileID)]
        )
        guard let values = rows.first else { return nil }
        let row = SQLiteRow(table: "source_files", values: values)
        return FileCheckpoint(
            fileID: try row.requiredString("file_id"),
            deviceID: try row.requiredInt64("device_id"),
            inode: try row.requiredInt64("inode"),
            path: try row.requiredString("path"),
            fileSize: try row.requiredInt64("file_size"),
            committedOffset: try row.requiredInt64("committed_offset"),
            generation: try row.requiredInt64("generation"),
            threadID: try row.optionalString("thread_id"),
            lastRecordAtMilliseconds: try row.optionalInt64("last_record_at_ms"),
            lastSuccessAtMilliseconds: try row.optionalInt64("last_success_at_ms"),
            formatStatus: try row.requiredString("format_status"),
            lastError: try row.optionalString("last_error")
        )
    }

    func threadCheckpoint(threadID: String) throws -> ThreadCheckpoint? {
        let rows = try database.query(
            sql: "SELECT * FROM thread_checkpoints WHERE thread_id = ?",
            bindings: [.text(threadID)]
        )
        guard let values = rows.first else { return nil }
        let row = SQLiteRow(table: "thread_checkpoints", values: values)
        let counters: TokenCounters?
        if let input = try row.optionalInt64("input_tokens"),
           let cached = try row.optionalInt64("cached_input_tokens"),
           let output = try row.optionalInt64("output_tokens"),
           let reasoning = try row.optionalInt64("reasoning_tokens") {
            counters = TokenCounters(input: input, cachedInput: cached, output: output, reasoning: reasoning)
        } else {
            counters = nil
        }
        return ThreadCheckpoint(
            threadID: try row.requiredString("thread_id"),
            currentModel: try row.optionalString("current_model"),
            currentPlan: try planResolution(from: row),
            counters: counters,
            counterSegment: try row.requiredInt64("counter_segment"),
            lastTokenAtMilliseconds: try row.optionalInt64("last_token_at_ms")
        )
    }

    func latestQuotas() throws -> [StoredQuotaEvent] {
        let rows = try database.query(
            sql: """
            SELECT fingerprint, observed_at_ms, thread_id, kind, window_minutes, remaining,
                   resets_at_ms, plan, plan_raw, plan_is_inferred, source_kind
            FROM quota_snapshots
            ORDER BY kind, observed_at_ms DESC, fingerprint DESC
            """
        )
        var seenKinds: Set<QuotaKind> = []
        var result: [StoredQuotaEvent] = []
        for values in rows {
            let row = SQLiteRow(table: "quota_snapshots", values: values)
            let kind = try row.requiredEnum("kind", as: QuotaKind.self)
            guard seenKinds.insert(kind).inserted else { continue }
            let plan = try SQLitePlanResolution.from(row: row)
            result.append(StoredQuotaEvent(
                fingerprint: try row.requiredString("fingerprint"),
                threadID: try row.requiredString("thread_id"),
                observation: QuotaObservation(
                    kind: kind,
                    observedAtMilliseconds: try row.requiredInt64("observed_at_ms"),
                    windowMinutes: Int(try row.requiredInt64("window_minutes")),
                    remaining: try row.requiredDouble("remaining"),
                    resetsAtMilliseconds: try row.optionalInt64("resets_at_ms"),
                    plan: plan
                ),
                sourceKind: try row.requiredEnum("source_kind", as: CodexSourceKind.self)
            ))
        }
        return result
    }

    func hourlyUsage() throws -> [StoredHourlyUsage] {
        let rows = try database.query(
            sql: "SELECT * FROM hourly_usage ORDER BY hour_start_ms, model, plan"
        )
        return try rows.map { values in
            let row = SQLiteRow(table: "hourly_usage", values: values)
            return StoredHourlyUsage(
                hourStartMilliseconds: try row.requiredInt64("hour_start_ms"),
                model: try row.requiredString("model"),
                plan: try row.requiredEnum("plan", as: PlanKind.self),
                uncachedInputTokens: try row.requiredInt64("uncached_input_tokens"),
                cachedInputTokens: try row.requiredInt64("cached_input_tokens"),
                visibleOutputTokens: try row.requiredInt64("visible_output_tokens"),
                reasoningTokens: try row.requiredInt64("reasoning_tokens"),
                totalTokens: try row.requiredInt64("total_tokens")
            )
        }
    }

    func usageEvents(
        fromMilliseconds: Int64? = nil,
        toMilliseconds: Int64? = nil
    ) throws -> [StoredUsageQueryRow] {
        var predicates: [String] = []
        var bindings: [SQLiteValue] = []
        if let fromMilliseconds {
            predicates.append("observed_at_ms >= ?")
            bindings.append(.integer(fromMilliseconds))
        }
        if let toMilliseconds {
            predicates.append("observed_at_ms < ?")
            bindings.append(.integer(toMilliseconds))
        }
        let whereClause = predicates.isEmpty ? "" : " WHERE \(predicates.joined(separator: " AND "))"
        let rows = try database.query(
            sql: """
            SELECT fingerprint, observed_at_ms, thread_id, model, plan, plan_raw, plan_is_inferred,
                   uncached_input_tokens, cached_input_tokens, visible_output_tokens,
                   reasoning_tokens, total_tokens
            FROM usage_events\(whereClause)
            ORDER BY observed_at_ms, fingerprint
            """,
            bindings: bindings
        )
        return try rows.map { values in
            let row = SQLiteRow(table: "usage_events", values: values)
            return StoredUsageQueryRow(
                fingerprint: try row.requiredString("fingerprint"),
                observedAtMilliseconds: try row.requiredInt64("observed_at_ms"),
                threadID: try row.requiredString("thread_id"),
                model: try row.requiredString("model"),
                plan: try SQLitePlanResolution.from(row: row),
                uncachedInputTokens: try row.requiredInt64("uncached_input_tokens"),
                cachedInputTokens: try row.requiredInt64("cached_input_tokens"),
                visibleOutputTokens: try row.requiredInt64("visible_output_tokens"),
                reasoningTokens: try row.requiredInt64("reasoning_tokens"),
                totalTokens: try row.requiredInt64("total_tokens")
            )
        }
    }

    func sessions() throws -> [StoredSession] {
        let rows = try database.query(sql: "SELECT * FROM sessions ORDER BY thread_id")
        return try rows.map { try storedSession(from: SQLiteRow(table: "sessions", values: $0)) }
    }

    func sessionQueryRows() throws -> [StoredSessionQueryRow] {
        let sessionRows = try database.query(sql: """
            SELECT s.*, sf.last_record_at_ms AS source_last_record_at_ms
            FROM sessions AS s
            LEFT JOIN source_files AS sf ON sf.file_id = s.source_file_id
            ORDER BY s.thread_id
            """)
        let tokenRows = try database.query(
            sql: "SELECT thread_id, total_tokens FROM usage_events ORDER BY thread_id, fingerprint"
        )
        var totals: [String: Int64] = [:]
        for values in tokenRows {
            let row = SQLiteRow(table: "usage_events", values: values)
            let threadID = try row.requiredString("thread_id")
            totals[threadID] = try checkedAdd(
                totals[threadID, default: 0],
                row.requiredInt64("total_tokens"),
                context: "usage_events.thread_total_tokens"
            )
        }
        return try sessionRows.map { values in
            let row = SQLiteRow(table: "sessions", values: values)
            let session = try storedSession(from: row)
            return StoredSessionQueryRow(
                session: session,
                sourceLastRecordAtMilliseconds: try row.optionalInt64("source_last_record_at_ms"),
                totalTokens: totals[session.threadID, default: 0]
            )
        }
    }

    func schemaVersions() throws -> [Int64] {
        try database.query(sql: "SELECT version FROM schema_migrations ORDER BY version")
            .map { try SQLiteRow(table: "schema_migrations", values: $0).requiredInt64("version") }
    }

    func schemaTables() throws -> [String] {
        try database.query(
            sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).map { try SQLiteRow(table: "sqlite_master", values: $0).requiredString("name") }
    }

    func schemaColumns(table: String) throws -> [String] {
        guard table.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return [] }
        return try database.query(sql: "PRAGMA table_info(\(table))")
            .map { try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name") }
    }

    private func migrate() throws {
        try database.inTransaction {
            try database.execute(sql: "CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY)")
            let versions = try database.query(sql: "SELECT version FROM schema_migrations ORDER BY version")
                .map { try SQLiteRow(table: "schema_migrations", values: $0).requiredInt64("version") }

            guard versions.last ?? 0 <= 1 else {
                throw UsageStoreError.unsupportedSchemaVersion(versions.last ?? 0)
            }
            if versions.contains(1) {
                try validateVersionOneSchema()
                return
            }

            for statement in Self.versionOneStatements {
                try database.execute(sql: statement)
            }
            try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (1)")
            try validateVersionOneSchema()
        }
    }

    @discardableResult
    private func insertUsageEvent(_ event: StoredUsageEvent, total: Int64) throws -> Int32 {
        try database.execute(
            sql: """
            INSERT INTO usage_events(
              fingerprint, observed_at_ms, thread_id, source_kind, model, plan, plan_raw,
              plan_is_inferred, uncached_input_tokens, cached_input_tokens,
              visible_output_tokens, reasoning_tokens, total_tokens, source_file_id, source_offset
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(fingerprint) DO NOTHING
            """,
            bindings: [
                .text(event.fingerprint), .integer(event.observedAtMilliseconds), .text(event.threadID),
                .text(event.sourceKind.rawValue), .text(event.model), .text(event.plan.kind.rawValue),
                event.plan.rawValue.sqliteValue, .integer(event.plan.isInferred ? 1 : 0),
                .integer(event.usage.uncachedInput), .integer(event.usage.cachedInput),
                .integer(event.usage.visibleOutput), .integer(event.usage.reasoning),
                .integer(total), .text(event.sourceFileID), .integer(event.sourceOffset)
            ]
        )
    }

    private func addToHourlyUsage(_ event: StoredUsageEvent, total: Int64) throws {
        let hourStart = event.observedAtMilliseconds - event.observedAtMilliseconds % 3_600_000
        let keyBindings: [SQLiteValue] = [
            .integer(hourStart), .text(event.model), .text(event.plan.kind.rawValue)
        ]
        let rows = try database.query(
            sql: """
            SELECT uncached_input_tokens, cached_input_tokens, visible_output_tokens,
                   reasoning_tokens, total_tokens
            FROM hourly_usage
            WHERE hour_start_ms = ? AND model = ? AND plan = ?
            """,
            bindings: keyBindings
        )

        guard let values = rows.first else {
            try database.execute(
                sql: """
                INSERT INTO hourly_usage(
                  hour_start_ms, model, plan, uncached_input_tokens, cached_input_tokens,
                  visible_output_tokens, reasoning_tokens, total_tokens
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: keyBindings + [
                    .integer(event.usage.uncachedInput), .integer(event.usage.cachedInput),
                    .integer(event.usage.visibleOutput), .integer(event.usage.reasoning), .integer(total)
                ]
            )
            return
        }

        let row = SQLiteRow(table: "hourly_usage", values: values)
        let uncachedInput = try checkedAdd(
            row.requiredInt64("uncached_input_tokens"),
            event.usage.uncachedInput,
            context: "hourly_usage.uncached_input_tokens"
        )
        let cachedInput = try checkedAdd(
            row.requiredInt64("cached_input_tokens"),
            event.usage.cachedInput,
            context: "hourly_usage.cached_input_tokens"
        )
        let visibleOutput = try checkedAdd(
            row.requiredInt64("visible_output_tokens"),
            event.usage.visibleOutput,
            context: "hourly_usage.visible_output_tokens"
        )
        let reasoning = try checkedAdd(
            row.requiredInt64("reasoning_tokens"),
            event.usage.reasoning,
            context: "hourly_usage.reasoning_tokens"
        )
        let updatedTotal = try checkedAdd(
            row.requiredInt64("total_tokens"),
            total,
            context: "hourly_usage.total_tokens"
        )

        try database.execute(
            sql: """
            UPDATE hourly_usage SET
              uncached_input_tokens = ?, cached_input_tokens = ?, visible_output_tokens = ?,
              reasoning_tokens = ?, total_tokens = ?
            WHERE hour_start_ms = ? AND model = ? AND plan = ?
            """,
            bindings: [
                .integer(uncachedInput), .integer(cachedInput), .integer(visibleOutput),
                .integer(reasoning), .integer(updatedTotal)
            ] + keyBindings
        )
    }

    private func insertQuotaEvent(_ event: StoredQuotaEvent) throws {
        let observation = event.observation
        guard observation.remaining.isFinite, (0...1).contains(observation.remaining) else {
            throw UsageStoreError.invalidQuotaRemaining
        }
        try database.execute(
            sql: """
            INSERT INTO quota_snapshots(
              fingerprint, observed_at_ms, thread_id, kind, window_minutes, remaining,
              resets_at_ms, plan, plan_raw, plan_is_inferred, source_kind
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(fingerprint) DO NOTHING
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
            INSERT INTO session_state_events(
              fingerprint, thread_id, turn_id, observed_at_ms, kind, source_file_id, source_offset
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(fingerprint) DO NOTHING
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
              archive_observed_at_ms, last_model, last_plan, source_file_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(thread_id) DO UPDATE SET
              source_kind = excluded.source_kind, created_at_ms = excluded.created_at_ms,
              updated_at_ms = excluded.updated_at_ms, activity_state = excluded.activity_state,
              archive_state = excluded.archive_state, child_edge_status = excluded.child_edge_status,
              active_turn_id = excluded.active_turn_id, last_activity_at_ms = excluded.last_activity_at_ms,
              last_event_key = excluded.last_event_key,
              archive_observed_at_ms = excluded.archive_observed_at_ms,
              last_model = excluded.last_model,
              last_plan = excluded.last_plan, source_file_id = excluded.source_file_id
            """,
            bindings: [
                .text(session.threadID), .text(session.sourceKind.rawValue),
                session.createdAtMilliseconds.sqliteValue, session.updatedAtMilliseconds.sqliteValue,
                .text(session.activity.rawValue), .text(session.archive.rawValue),
                session.childEdgeStatus.sqliteValue, session.activeTurnID.sqliteValue,
                session.state.lastActivityAtMilliseconds.sqliteValue,
                session.state.lastActivityEventKey.sqliteValue,
                session.state.archiveObservedAtMilliseconds.sqliteValue,
                session.lastModel.sqliteValue,
                (session.lastPlan?.rawValue).sqliteValue, session.sourceFileID.sqliteValue
            ]
        )
    }

    private func upsertThreadCheckpoint(_ checkpoint: ThreadCheckpoint) throws {
        try database.execute(
            sql: """
            INSERT INTO thread_checkpoints(
              thread_id, current_model, plan, plan_raw, plan_is_inferred,
              input_tokens, cached_input_tokens, output_tokens,
              reasoning_tokens, counter_segment, last_token_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(thread_id) DO UPDATE SET
              current_model = excluded.current_model, plan = excluded.plan,
              plan_raw = excluded.plan_raw, plan_is_inferred = excluded.plan_is_inferred,
              input_tokens = excluded.input_tokens,
              cached_input_tokens = excluded.cached_input_tokens, output_tokens = excluded.output_tokens,
              reasoning_tokens = excluded.reasoning_tokens, counter_segment = excluded.counter_segment,
              last_token_at_ms = excluded.last_token_at_ms
            """,
            bindings: [
                .text(checkpoint.threadID), checkpoint.currentModel.sqliteValue,
                (checkpoint.currentPlan?.kind.rawValue).sqliteValue,
                checkpoint.currentPlan.flatMap(\.rawValue).sqliteValue,
                checkpoint.currentPlan.map { $0.isInferred ? Int64(1) : Int64(0) }.sqliteValue,
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
              thread_id, last_record_at_ms, last_success_at_ms, format_status, last_error
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_id) DO UPDATE SET
              device_id = excluded.device_id, inode = excluded.inode, path = excluded.path,
              file_size = excluded.file_size, committed_offset = excluded.committed_offset,
              generation = excluded.generation, thread_id = excluded.thread_id,
              last_record_at_ms = excluded.last_record_at_ms,
              last_success_at_ms = excluded.last_success_at_ms, format_status = excluded.format_status,
              last_error = excluded.last_error
            """,
            bindings: [
                .text(checkpoint.fileID), .integer(checkpoint.deviceID), .integer(checkpoint.inode),
                .text(checkpoint.path), .integer(checkpoint.fileSize), .integer(checkpoint.committedOffset),
                .integer(checkpoint.generation), checkpoint.threadID.sqliteValue,
                checkpoint.lastRecordAtMilliseconds.sqliteValue,
                checkpoint.lastSuccessAtMilliseconds.sqliteValue, .text(checkpoint.formatStatus),
                checkpoint.lastError.sqliteValue
            ]
        )
    }

    private func validatedTotal(for usage: TokenUsageDelta) throws -> Int64 {
        let components = [
            ("uncached_input_tokens", usage.uncachedInput),
            ("cached_input_tokens", usage.cachedInput),
            ("visible_output_tokens", usage.visibleOutput),
            ("reasoning_tokens", usage.reasoning)
        ]
        var total: Int64 = 0
        for (name, value) in components {
            guard value >= 0 else {
                throw UsageStoreError.invalidUsageComponent(name: name, value: value)
            }
            total = try checkedAdd(total, value, context: "usage_events.total_tokens")
        }
        return total
    }

    private func checkedAdd(_ left: Int64, _ right: Int64, context: String) throws -> Int64 {
        let (sum, overflow) = left.addingReportingOverflow(right)
        guard !overflow else {
            throw UsageStoreError.tokenOverflow(context: context)
        }
        return sum
    }

    private func count(table: String) throws -> Int64 {
        let rows = try database.query(sql: "SELECT COUNT(*) AS count FROM \(table)")
        guard let values = rows.first else {
            throw UsageStoreError.corruptColumn(
                table: table,
                column: "count",
                expected: "INTEGER",
                actual: nil
            )
        }
        return try SQLiteRow(table: table, values: values).requiredInt64("count")
    }

    private static let versionOneStatements = [
        """
        CREATE TABLE source_files(
          file_id TEXT PRIMARY KEY, device_id INTEGER NOT NULL, inode INTEGER NOT NULL,
          path TEXT NOT NULL, file_size INTEGER NOT NULL DEFAULT 0,
          committed_offset INTEGER NOT NULL DEFAULT 0,
          generation INTEGER NOT NULL DEFAULT 0, thread_id TEXT, last_record_at_ms INTEGER,
          last_success_at_ms INTEGER, format_status TEXT NOT NULL DEFAULT 'supported', last_error TEXT
        )
        """,
        """
        CREATE TABLE thread_checkpoints(
          thread_id TEXT PRIMARY KEY, current_model TEXT,
          plan TEXT, plan_raw TEXT, plan_is_inferred INTEGER,
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
          last_event_key TEXT, archive_observed_at_ms INTEGER,
          last_model TEXT, last_plan TEXT, source_file_id TEXT
        )
        """,
        """
        CREATE TABLE source_status(
          source_kind TEXT PRIMARY KEY, state TEXT NOT NULL, detail TEXT,
          last_success_at_ms INTEGER, processed_file_count INTEGER NOT NULL DEFAULT 0
        )
        """
    ]

    private func planResolution(from row: SQLiteRow) throws -> PlanResolution? {
        try SQLitePlanResolution.optional(from: row)
    }

    private func storedSession(from row: SQLiteRow) throws -> StoredSession {
        let threadID = try row.requiredString("thread_id")
        return StoredSession(
            threadID: threadID,
            sourceKind: try row.requiredEnum("source_kind", as: CodexSourceKind.self),
            createdAtMilliseconds: try row.optionalInt64("created_at_ms"),
            updatedAtMilliseconds: try row.optionalInt64("updated_at_ms"),
            state: SessionStateSnapshot(
                threadID: threadID,
                activity: try row.requiredEnum("activity_state", as: SessionActivityState.self),
                archive: try row.requiredEnum("archive_state", as: SessionArchiveState.self),
                childEdgeStatus: try row.optionalString("child_edge_status"),
                activeTurnID: try row.optionalString("active_turn_id"),
                lastActivityAtMilliseconds: try row.optionalInt64("last_activity_at_ms"),
                lastActivityEventKey: try row.optionalString("last_event_key"),
                archiveObservedAtMilliseconds: try row.optionalInt64("archive_observed_at_ms")
            ),
            lastModel: try row.optionalString("last_model"),
            lastPlan: try row.optionalEnum("last_plan", as: PlanKind.self),
            sourceFileID: try row.optionalString("source_file_id")
        )
    }

    private func validateVersionOneSchema() throws {
        let requiredColumns: [(table: String, columns: [String])] = [
            ("source_files", ["thread_id"]),
            ("thread_checkpoints", ["plan", "plan_raw", "plan_is_inferred"]),
            ("sessions", ["archive_observed_at_ms"])
        ]
        for requirement in requiredColumns {
            let rows = try database.query(sql: "PRAGMA table_info(\(requirement.table))")
            let existing = try Set(rows.map {
                try SQLiteRow(table: "pragma_table_info", values: $0).requiredString("name")
            })
            let missing = requirement.columns.filter { !existing.contains($0) }
            if !missing.isEmpty {
                throw UsageStoreError.rebuildRequired(
                    table: requirement.table,
                    missingColumns: missing
                )
            }
        }
    }
}

enum UsageStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int64)
    case rebuildRequired(table: String, missingColumns: [String])
    case invalidFileCheckpoint(fileSize: Int64, committedOffset: Int64)
    case invalidUsageComponent(name: String, value: Int64)
    case invalidQuotaRemaining
    case tokenOverflow(context: String)
    case corruptColumn(table: String, column: String, expected: String, actual: SQLiteValue?)
    case corruptEnum(table: String, column: String, value: String)
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

private struct SQLiteRow {
    let table: String
    let values: [String: SQLiteValue]

    func requiredInt64(_ column: String) throws -> Int64 {
        guard case let .integer(value)? = values[column] else {
            throw corruptColumn(column, expected: "INTEGER")
        }
        return value
    }

    func optionalInt64(_ column: String) throws -> Int64? {
        switch values[column] {
        case let .integer(value):
            return value
        case .null:
            return nil
        default:
            throw corruptColumn(column, expected: "INTEGER or NULL")
        }
    }

    func requiredDouble(_ column: String) throws -> Double {
        guard case let .real(value)? = values[column] else {
            throw corruptColumn(column, expected: "REAL")
        }
        return value
    }

    func requiredString(_ column: String) throws -> String {
        guard case let .text(value)? = values[column] else {
            throw corruptColumn(column, expected: "TEXT")
        }
        return value
    }

    func optionalString(_ column: String) throws -> String? {
        switch values[column] {
        case let .text(value):
            return value
        case .null:
            return nil
        default:
            throw corruptColumn(column, expected: "TEXT or NULL")
        }
    }

    func requiredEnum<T>(_ column: String, as type: T.Type) throws -> T
    where T: RawRepresentable, T.RawValue == String {
        let value = try requiredString(column)
        guard let result = T(rawValue: value) else {
            throw UsageStoreError.corruptEnum(table: table, column: column, value: value)
        }
        return result
    }

    func optionalEnum<T>(_ column: String, as type: T.Type) throws -> T?
    where T: RawRepresentable, T.RawValue == String {
        guard let value = try optionalString(column) else { return nil }
        guard let result = T(rawValue: value) else {
            throw UsageStoreError.corruptEnum(table: table, column: column, value: value)
        }
        return result
    }

    private func corruptColumn(_ column: String, expected: String) -> UsageStoreError {
        UsageStoreError.corruptColumn(
            table: table,
            column: column,
            expected: expected,
            actual: values[column]
        )
    }
}

private enum SQLitePlanResolution {
    static func from(row: SQLiteRow) throws -> PlanResolution {
        guard let result = try optional(from: row) else {
            throw UsageStoreError.corruptColumn(
                table: row.table,
                column: "plan",
                expected: "TEXT",
                actual: row.values["plan"]
            )
        }
        return result
    }

    static func optional(from row: SQLiteRow) throws -> PlanResolution? {
        guard let kind = try row.optionalEnum("plan", as: PlanKind.self) else { return nil }
        guard let inferred = try row.optionalInt64("plan_is_inferred"), inferred == 0 || inferred == 1 else {
            throw UsageStoreError.corruptColumn(
                table: row.table,
                column: "plan_is_inferred",
                expected: "INTEGER boolean",
                actual: row.values["plan_is_inferred"]
            )
        }
        return PlanResolution(
            kind: kind,
            rawValue: try row.optionalString("plan_raw"),
            isInferred: inferred == 1
        )
    }
}
