import Foundation
import XCTest
@testable import SpendScope

final class UsageStoreTests: XCTestCase {
    func testBatchIsIdempotentAndCheckpointAdvancesAtomically() throws {
        let store = try makeStore()
        let event = StoredUsageEvent.fixture(fingerprint: "usage-1", total: 100)
        let batch = ImportBatch(
            file: .fixture(committedOffset: 80),
            usageEvents: [event],
            quotaEvents: [],
            stateEvents: [],
            sessions: [],
            threadCheckpoints: []
        )

        try store.commit(batch)
        try store.commit(batch)

        XCTAssertEqual(try store.totalUsage(), 100)
        XCTAssertEqual(try store.usageEventCount(), 1)
        XCTAssertEqual(try store.hourlyUsage().map(\.totalTokens), [100])
        XCTAssertEqual(try store.fileCheckpoint(fileID: batch.file.fileID)?.committedOffset, 80)
    }

    func testUsageEventsPersistOnlyProjectIdentityAndDisplayName() throws {
        let store = try makeStore()
        let project = ProjectIdentity(
            id: "hashed-project-id",
            name: "SpendScope",
            repositoryID: "hashed-repository-id"
        )
        try store.commit(ImportBatch(
            file: .fixture(committedOffset: 80),
            usageEvents: [.fixture(fingerprint: "project-usage", total: 100, project: project)],
            quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
        ))

        XCTAssertEqual(try store.usageEvents().first?.project, project)
        let columns = try store.schemaColumns(table: "usage_events")
        XCTAssertFalse(columns.contains("cwd"))
        XCTAssertFalse(columns.contains("project_path"))
    }

    func testStoresOrthogonalSessionFactsWithoutMessageColumns() throws {
        let store = try makeStore()
        try store.commit(.fixture(session: .fixture(
            activity: .completed,
            archive: .archived,
            childEdgeStatus: "open"
        )))

        let session = try XCTUnwrap(store.sessions().first)
        XCTAssertEqual(session.activity, .completed)
        XCTAssertEqual(session.archive, .archived)
        XCTAssertEqual(session.childEdgeStatus, "open")

        let columns = try store.schemaColumns(table: "sessions")
        XCTAssertFalse(columns.contains("title"))
        XCTAssertFalse(columns.contains("message"))
        XCTAssertFalse(columns.contains("prompt"))
        XCTAssertFalse(columns.contains("response"))
    }

    func testMigrationCreatesExactVersionNineStorageSurface() throws {
        let url = temporaryDatabaseURL()
        _ = try UsageStore(databaseURL: url)
        let store = try UsageStore(databaseURL: url)

        XCTAssertEqual(try store.schemaVersions(), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(
            Set(try store.schemaColumns(table: "source_files")),
            Set([
                "file_id", "device_id", "inode", "path", "file_size", "committed_offset",
                "generation", "thread_id", "last_record_at_ms", "last_success_at_ms",
                "format_status", "last_error", "current_model", "plan", "plan_raw",
                "plan_is_inferred", "input_tokens", "cached_input_tokens", "output_tokens",
                "reasoning_tokens", "counter_segment", "last_token_at_ms",
                "activity_committed_offset", "project_id", "project_name", "repository_id"
            ])
        )
        XCTAssertEqual(
            Set(try store.schemaColumns(table: "thread_checkpoints")),
            Set([
                "thread_id", "current_model", "plan", "plan_raw", "plan_is_inferred",
                "input_tokens", "cached_input_tokens", "output_tokens", "reasoning_tokens",
                "counter_segment", "last_token_at_ms"
            ])
        )
        XCTAssertEqual(
            Set(try store.schemaColumns(table: "sessions")),
            Set([
                "thread_id", "source_kind", "created_at_ms", "updated_at_ms",
                "activity_state", "archive_state", "child_edge_status", "active_turn_id",
                "last_activity_at_ms", "last_event_key", "archive_observed_at_ms",
                "last_model", "last_plan", "source_file_id"
            ])
        )
        XCTAssertEqual(
            Set(try store.schemaColumns(table: "activity_events")),
            Set([
                "fingerprint", "observed_at_ms", "thread_id", "turn_id", "kind", "name",
                "source_kind", "source_file_id", "source_offset"
            ])
        )
        XCTAssertTrue(try store.schemaColumns(table: "usage_events").contains("project_id"))
        XCTAssertTrue(try store.schemaColumns(table: "usage_events").contains("project_name"))
        XCTAssertTrue(try store.schemaColumns(table: "usage_events").contains("repository_id"))
        XCTAssertFalse(try store.schemaColumns(table: "usage_events").contains("cwd"))
        XCTAssertFalse(try store.schemaColumns(table: "usage_events").contains("project_path"))
        XCTAssertEqual(
            Set(try store.schemaTables()),
            Set([
                "schema_migrations", "source_files", "thread_checkpoints", "usage_events",
                "hourly_usage", "quota_snapshots", "session_state_events", "sessions",
                "source_status", "activity_events", "account_rate_limit_cache"
            ])
        )
        XCTAssertEqual(
            Set(try store.schemaColumns(table: "account_rate_limit_cache")),
            Set([
                "window_minutes", "used_percent", "resets_at_seconds", "plan_raw",
                "observed_at_ms"
            ])
        )
    }

    func testPersistsQuotaSessionStateAndThreadCheckpointInOneBatch() throws {
        let store = try makeStore()
        let batch = ImportBatch(
            file: .fixture(committedOffset: 160),
            usageEvents: [.fixture(fingerprint: "usage-all", total: 40)],
            quotaEvents: [.fixture()],
            stateEvents: [.fixture()],
            sessions: [.fixture(activity: .running, archive: .active, childEdgeStatus: nil)],
            threadCheckpoints: [.fixture()]
        )

        try store.commit(batch)

        XCTAssertEqual(try store.quotaEventCount(), 1)
        XCTAssertEqual(try store.sessionStateEventCount(), 1)
        XCTAssertEqual(try store.sessions().first?.activeTurnID, "turn-1")
        XCTAssertEqual(try store.threadCheckpoint(threadID: "thread-1")?.counters?.input, 100)
        XCTAssertEqual(try store.threadCheckpoint(threadID: "thread-1")?.currentPlan?.kind, .plus)
        XCTAssertEqual(try store.threadCheckpoint(threadID: "thread-1")?.currentPlan?.rawValue, "plus")
        XCTAssertFalse(try XCTUnwrap(store.threadCheckpoint(threadID: "thread-1")?.currentPlan).isInferred)
        XCTAssertEqual(try store.fileCheckpoint(fileID: batch.file.fileID)?.threadID, "thread-1")
        XCTAssertEqual(try store.sessions().first?.state.archiveObservedAtMilliseconds, 2_000)
        XCTAssertEqual(try store.fileCheckpoint(fileID: batch.file.fileID)?.committedOffset, 160)
    }

    func testLatestQuotasUsesNewestTimeThenFingerprintTieBreakPerKind() throws {
        let store = try makeStore()
        let batch = ImportBatch(
            file: .fixture(committedOffset: 160),
            usageEvents: [],
            quotaEvents: [
                .fixture(fingerprint: "older", observedAtMilliseconds: 1_000, remaining: 0.9),
                .fixture(fingerprint: "tie-a", observedAtMilliseconds: 2_000, remaining: 0.7),
                .fixture(fingerprint: "tie-z", observedAtMilliseconds: 2_000, remaining: 0.6),
                .fixture(
                    fingerprint: "weekly",
                    kind: .weekly,
                    observedAtMilliseconds: 1_500,
                    remaining: 0.5
                )
            ],
            stateEvents: [],
            sessions: [],
            threadCheckpoints: []
        )

        try store.commit(batch)

        let quotas = try store.latestQuotas()
        XCTAssertEqual(quotas.map(\.fingerprint), ["tie-z", "weekly"])
        XCTAssertEqual(quotas.map(\.observation.kind), [.fiveHour, .weekly])
        XCTAssertEqual(quotas.map(\.observation.remaining), [0.6, 0.5])
    }

    func testOfficialAccountRateLimitsRoundTripAndReplaceAtomically() throws {
        let store = try makeStore()
        let first = CodexAccountRateLimits(
            planRaw: "prolite",
            windows: [
                RawQuotaWindow(
                    windowMinutes: 300, usedPercent: 12,
                    resetsAtSeconds: 2_000
                ),
                RawQuotaWindow(
                    windowMinutes: 10_080, usedPercent: 8,
                    resetsAtSeconds: 3_000
                )
            ],
            observedAt: Date(timeIntervalSince1970: 1_000.125)
        )
        try store.persistAccountRateLimits(first)
        XCTAssertEqual(try store.accountRateLimits(), first)

        let replacement = CodexAccountRateLimits(
            planRaw: "plus",
            windows: [RawQuotaWindow(
                windowMinutes: 10_080, usedPercent: 25,
                resetsAtSeconds: 4_000
            )],
            observedAt: Date(timeIntervalSince1970: 2_000)
        )
        try store.persistAccountRateLimits(replacement)

        XCTAssertEqual(try store.accountRateLimits(), replacement)
    }

    func testUsageQueryUsesInclusiveStartExclusiveEndAndStableOrdering() throws {
        let store = try makeStore()
        try store.commit(ImportBatch(
            file: .fixture(committedOffset: 160),
            usageEvents: [
                .fixture(fingerprint: "before", observedAtMilliseconds: 999, total: 1),
                .fixture(fingerprint: "tie-z", observedAtMilliseconds: 1_000, total: 2),
                .fixture(fingerprint: "tie-a", observedAtMilliseconds: 1_000, total: 3),
                .fixture(fingerprint: "end", observedAtMilliseconds: 2_000, total: 4)
            ],
            quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
        ))

        let rows = try store.usageEvents(fromMilliseconds: 1_000, toMilliseconds: 2_000)

        XCTAssertEqual(rows.map(\.fingerprint), ["tie-a", "tie-z"])
        XCTAssertEqual(rows.map(\.totalTokens), [3, 2])
    }

    func testSessionQueryUsesTheSessionsExactSourceFileCheckpoint() throws {
        let store = try makeStore()
        try store.commit(ImportBatch(
            file: .fixture(
                fileID: "session-file", committedOffset: 10,
                threadID: "precise-thread", lastRecordAtMilliseconds: 600_000
            ),
            usageEvents: [.fixture(
                fingerprint: "precise-usage", threadID: "precise-thread", total: 42
            )],
            quotaEvents: [], stateEvents: [],
            sessions: [.fixture(
                threadID: "precise-thread", sourceFileID: "session-file",
                activity: .running, archive: .active, childEdgeStatus: nil
            )],
            threadCheckpoints: []
        ))
        try store.commit(ImportBatch(
            file: .fixture(
                fileID: "unrelated-file", committedOffset: 10,
                threadID: "precise-thread", lastRecordAtMilliseconds: 999_000
            ),
            usageEvents: [], quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
        ))

        let row = try XCTUnwrap(store.sessionQueryRows().first)

        XCTAssertEqual(row.sourceLastRecordAtMilliseconds, 600_000)
        XCTAssertEqual(row.totalTokens, 42)
    }

    func testSourceFactsUseOnlyStoredSafeHealthAndCheckpointData() throws {
        let store = try makeStore()
        let desktopSession = StoredSession(
            threadID: "desktop-thread",
            sourceKind: .desktop,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            state: .empty(threadID: "desktop-thread"),
            lastModel: nil,
            lastPlan: nil,
            sourceFileID: "file-1"
        )
        try store.commit(ImportBatch(
            file: .fixture(committedOffset: 10),
            usageEvents: [.fixture(fingerprint: "cli-usage", total: 42)],
            quotaEvents: [], stateEvents: [], sessions: [desktopSession], threadCheckpoints: []
        ))
        try store.recordIndexHealth(.degraded("sensitive internal detail"), processedFileCount: 1)

        let facts = try store.sourceFacts()

        XCTAssertTrue(facts.hasCLIData)
        XCTAssertTrue(facts.hasDesktopData)
        XCTAssertEqual(facts.indexHealth, .degraded("index-degraded"))
        XCTAssertEqual(facts.lastSuccessfulRefreshMilliseconds, 3_000)
    }

    func testCurrentFileHealthClearsRemovedHistoricalErrorAfterSuccessfulDiscovery() throws {
        let store = try makeStore()
        try store.persistSourceStatus(
            indexHealth: .missing,
            discoveredFileIDs: ["removed-bad"],
            issues: [.init(kind: .read, fileID: "removed-bad", detail: "read-failed")],
            processedFileCount: 1
        )
        XCTAssertTrue(try store.sourceFacts().hasDegradedFiles)

        try store.persistSourceStatus(
            indexHealth: .missing,
            discoveredFileIDs: [],
            issues: [],
            processedFileCount: 0
        )
        let recovered = try store.sourceFacts()
        XCTAssertFalse(recovered.hasDegradedFiles)
        XCTAssertFalse(recovered.hasUnsupportedFiles)
    }

    func testCurrentUnsupportedFileHealthIsPersistedWithoutRawDetail() throws {
        let store = try makeStore()
        try store.commit(ImportBatch(
            file: .fixture(
                fileID: "current-unsupported", committedOffset: 0,
                formatStatus: "error", lastError: "missing-thread-context"
            ),
            usageEvents: [], quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
        ))

        try store.persistSourceStatus(
            indexHealth: .available,
            discoveredFileIDs: ["current-unsupported"],
            issues: [],
            processedFileCount: 1
        )
        let facts = try store.sourceFacts()

        XCTAssertTrue(facts.hasUnsupportedFiles)
        XCTAssertFalse(facts.hasDegradedFiles)
    }

    func testCurrentReadFailureWithoutCheckpointSurvivesUnrelatedForegroundPass() throws {
        let store = try makeStore()
        try store.persistSourceStatus(
            indexHealth: .missing,
            discoveredFileIDs: ["old-unread", "newest"],
            issues: [.init(kind: .read, fileID: "old-unread", detail: "raw-sensitive")],
            processedFileCount: 1
        )

        try store.persistSourceStatus(
            indexHealth: .missing,
            discoveredFileIDs: ["old-unread", "newest"],
            issues: [],
            processedFileCount: 1
        )

        XCTAssertTrue(try store.sourceFacts().hasDegradedFiles)
    }

    func testSuccessfulCheckpointRetryClearsPersistedCurrentReadFailure() throws {
        let store = try makeStore()
        try store.persistSourceStatus(
            indexHealth: .missing,
            discoveredFileIDs: ["retry-file"],
            issues: [.init(kind: .read, fileID: "retry-file", detail: "read-failed")],
            processedFileCount: 0
        )
        try store.commit(ImportBatch(
            file: .fixture(fileID: "retry-file", committedOffset: 10),
            usageEvents: [], quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
        ))

        try store.persistSourceStatus(
            indexHealth: .missing,
            discoveredFileIDs: ["retry-file"],
            issues: [],
            processedFileCount: 1
        )

        XCTAssertFalse(try store.sourceFacts().hasDegradedFiles)
    }

    func testEmptyCurrentInventoryPreservesHistoricalLastSuccessfulRefresh() throws {
        let store = try makeStore()
        try store.commit(ImportBatch(
            file: .fixture(fileID: "historical-success", committedOffset: 10),
            usageEvents: [], quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
        ))

        try store.persistSourceStatus(
            indexHealth: .missing,
            discoveredFileIDs: [],
            issues: [],
            processedFileCount: 0
        )

        XCTAssertEqual(try store.sourceFacts().lastSuccessfulRefreshMilliseconds, 3_000)
    }

    func testExistingVersionOneIsRebuiltIntoVersionNineStorage() throws {
        let url = temporaryDatabaseURL()
        let database = try SQLiteDatabase(url: url)
        try database.execute(sql: "CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY)")
        try database.execute(sql: "INSERT INTO schema_migrations(version) VALUES (1)")
        try database.execute(sql: """
            CREATE TABLE source_files(
              file_id TEXT PRIMARY KEY, device_id INTEGER NOT NULL, inode INTEGER NOT NULL,
              path TEXT NOT NULL, file_size INTEGER NOT NULL, committed_offset INTEGER NOT NULL,
              generation INTEGER NOT NULL, last_record_at_ms INTEGER, last_success_at_ms INTEGER,
              format_status TEXT NOT NULL, last_error TEXT
            )
            """)
        try database.execute(sql: """
            INSERT INTO source_files(
              file_id, device_id, inode, path, file_size, committed_offset, generation,
              format_status
            ) VALUES ('legacy', 1, 1, '/legacy.jsonl', 10, 10, 0, 'supported')
            """)

        let store = try UsageStore(databaseURL: url)

        XCTAssertEqual(try store.schemaVersions(), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertNil(try store.fileCheckpoint(fileID: "legacy"))
        XCTAssertTrue(try store.schemaColumns(table: "source_files").contains("input_tokens"))
        XCTAssertTrue(try store.schemaColumns(table: "source_files").contains("activity_committed_offset"))
    }

    func testVersionTwoToEightMigrationClearsDerivedDataForSemanticRebuild() throws {
        let url = temporaryDatabaseURL()
        do {
            let store = try UsageStore(databaseURL: url)
            try store.commit(ImportBatch(
                file: .fixture(committedOffset: 10, activityCommittedOffset: 10),
                usageEvents: [.fixture(fingerprint: "preserved-v2-usage", total: 321)],
                quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
            ))
        }
        let database = try SQLiteDatabase(url: url)
        try database.execute(sql: "DROP INDEX usage_events_project_time_idx")
        try database.execute(sql: "ALTER TABLE usage_events DROP COLUMN repository_id")
        try database.execute(sql: "ALTER TABLE usage_events DROP COLUMN project_id")
        try database.execute(sql: "ALTER TABLE usage_events DROP COLUMN project_name")
        try database.execute(sql: "ALTER TABLE source_files DROP COLUMN repository_id")
        try database.execute(sql: "ALTER TABLE source_files DROP COLUMN project_id")
        try database.execute(sql: "ALTER TABLE source_files DROP COLUMN project_name")
        try database.execute(sql: "DROP TABLE activity_events")
        try database.execute(sql: "ALTER TABLE source_files DROP COLUMN activity_committed_offset")
        try database.execute(sql: "DELETE FROM schema_migrations WHERE version IN (3, 4, 5, 6, 7, 8, 9)")

        let migrated = try UsageStore(databaseURL: url)

        XCTAssertEqual(try migrated.schemaVersions(), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(try migrated.totalUsage(), 0)
        XCTAssertEqual(try migrated.usageEventCount(), 0)
        XCTAssertNil(try migrated.fileCheckpoint(fileID: "file-1"))
    }

    func testVersionThreeToEightMigrationClearsDerivedSnapshots() throws {
        let url = temporaryDatabaseURL()
        do {
            let store = try UsageStore(databaseURL: url)
            try store.commit(ImportBatch(
                file: .fixture(committedOffset: 10, activityCommittedOffset: 10),
                usageEvents: [.fixture(fingerprint: "v3-usage", total: 321)],
                quotaEvents: [.fixture(fingerprint: "v3-mixed-quota")],
                stateEvents: [], sessions: [], threadCheckpoints: []
            ))
        }
        let database = try SQLiteDatabase(url: url)
        try database.execute(sql: "DROP INDEX usage_events_project_time_idx")
        try database.execute(sql: "ALTER TABLE usage_events DROP COLUMN repository_id")
        try database.execute(sql: "ALTER TABLE usage_events DROP COLUMN project_id")
        try database.execute(sql: "ALTER TABLE usage_events DROP COLUMN project_name")
        try database.execute(sql: "ALTER TABLE source_files DROP COLUMN repository_id")
        try database.execute(sql: "ALTER TABLE source_files DROP COLUMN project_id")
        try database.execute(sql: "ALTER TABLE source_files DROP COLUMN project_name")
        try database.execute(sql: "DELETE FROM schema_migrations WHERE version IN (4, 5, 6, 7, 8, 9)")

        let migrated = try UsageStore(databaseURL: url)

        XCTAssertEqual(try migrated.schemaVersions(), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(try migrated.totalUsage(), 0)
        XCTAssertEqual(try migrated.usageEventCount(), 0)
        XCTAssertEqual(try migrated.quotaEventCount(), 0)
        XCTAssertNil(try migrated.fileCheckpoint(fileID: "file-1"))
    }

    func testVersionFiveToEightMigrationClearsTimestampBasedFingerprints() throws {
        let url = temporaryDatabaseURL()
        do {
            let store = try UsageStore(databaseURL: url)
            try store.commit(ImportBatch(
                file: .fixture(committedOffset: 10, activityCommittedOffset: 10),
                usageEvents: [.fixture(fingerprint: "legacy-timestamp-fingerprint", total: 321)],
                quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
            ))
        }
        let database = try SQLiteDatabase(url: url)
        try database.execute(sql: "ALTER TABLE usage_events DROP COLUMN repository_id")
        try database.execute(sql: "ALTER TABLE source_files DROP COLUMN repository_id")
        try database.execute(sql: "DELETE FROM schema_migrations WHERE version IN (6, 7, 8, 9)")

        let migrated = try UsageStore(databaseURL: url)

        XCTAssertEqual(try migrated.schemaVersions(), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(try migrated.totalUsage(), 0)
        XCTAssertEqual(try migrated.usageEventCount(), 0)
        XCTAssertNil(try migrated.fileCheckpoint(fileID: "file-1"))
    }

    func testVersionSevenToEightMigrationRebuildsEmbeddedRepositoryIdentity() throws {
        let url = temporaryDatabaseURL()
        do {
            let store = try UsageStore(databaseURL: url)
            try store.commit(ImportBatch(
                file: .fixture(committedOffset: 10, activityCommittedOffset: 10),
                usageEvents: [.fixture(fingerprint: "missing-embedded-repository", total: 321)],
                quotaEvents: [], stateEvents: [], sessions: [], threadCheckpoints: []
            ))
        }
        let database = try SQLiteDatabase(url: url)
        try database.execute(sql: "DELETE FROM schema_migrations WHERE version IN (8, 9)")

        let migrated = try UsageStore(databaseURL: url)

        XCTAssertEqual(try migrated.schemaVersions(), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(try migrated.totalUsage(), 0)
        XCTAssertNil(try migrated.fileCheckpoint(fileID: "file-1"))
    }

    func testActivityEventsAreIdempotentPrivateAndRankedWithStableBoundaries() throws {
        let store = try makeStore()
        let events = [
            StoredActivityEvent.fixture(
                fingerprint: "skill-a-1", observedAtMilliseconds: 1_000,
                kind: .skill, name: "alpha"
            ),
            StoredActivityEvent.fixture(
                fingerprint: "skill-a-2", observedAtMilliseconds: 2_000,
                kind: .skill, name: "alpha"
            ),
            StoredActivityEvent.fixture(
                fingerprint: "skill-b", observedAtMilliseconds: 2_000,
                kind: .skill, name: "beta"
            ),
            StoredActivityEvent.fixture(
                fingerprint: "tool-z", observedAtMilliseconds: 3_000,
                kind: .tool, name: "zeta"
            )
        ]
        let batch = ImportBatch(
            file: .fixture(committedOffset: 10, activityCommittedOffset: 10),
            usageEvents: [], quotaEvents: [], stateEvents: [],
            activityEvents: events, sessions: [], threadCheckpoints: []
        )

        try store.commit(batch)
        try store.commit(batch)

        XCTAssertEqual(try store.activityEventCount(), 4)
        XCTAssertEqual(
            try store.activityCounts(
                kind: .skill, fromMilliseconds: 1_000, toMilliseconds: 3_000
            ),
            [StoredActivityCount(name: "alpha", count: 2), StoredActivityCount(name: "beta", count: 1)]
        )
        XCTAssertTrue(try store.activityCounts(
            kind: .tool, fromMilliseconds: nil, toMilliseconds: 3_000
        ).isEmpty, "Upper time boundary must stay exclusive")
        XCTAssertEqual(try store.fileCheckpoint(fileID: batch.file.fileID)?.activityCommittedOffset, 10)

        let columns = try store.schemaColumns(table: "activity_events")
        XCTAssertFalse(columns.contains("arguments"))
        XCTAssertFalse(columns.contains("input"))
        XCTAssertFalse(columns.contains("output"))
        XCTAssertFalse(columns.contains("prompt"))
        XCTAssertFalse(columns.contains("path"))
    }

    func testFailureRollsBackEventsAggregateSessionsAndCheckpoints() throws {
        let store = try makeStore()
        try store.commit(ImportBatch(
            file: .fixture(committedOffset: 10),
            usageEvents: [.fixture(fingerprint: "usage-initial", total: 100)],
            quotaEvents: [],
            stateEvents: [],
            sessions: [],
            threadCheckpoints: []
        ))

        let failingBatch = ImportBatch(
            file: .fixture(committedOffset: 201),
            usageEvents: [.fixture(fingerprint: "usage-rollback", total: 1)],
            quotaEvents: [.fixture(fingerprint: "quota-rollback")],
            stateEvents: [.fixture(fingerprint: "state-rollback")],
            sessions: [.fixture(activity: .completed, archive: .archived, childEdgeStatus: "closed")],
            threadCheckpoints: [.fixture(counterSegment: 2)]
        )

        XCTAssertThrowsError(try store.commit(failingBatch))
        XCTAssertEqual(try store.totalUsage(), 100)
        XCTAssertEqual(try store.hourlyUsage().map(\.totalTokens), [100])
        XCTAssertEqual(try store.usageEventCount(), 1)
        XCTAssertEqual(try store.quotaEventCount(), 0)
        XCTAssertEqual(try store.sessionStateEventCount(), 0)
        XCTAssertTrue(try store.sessions().isEmpty)
        XCTAssertNil(try store.threadCheckpoint(threadID: "thread-1"))
        XCTAssertEqual(try store.fileCheckpoint(fileID: failingBatch.file.fileID)?.committedOffset, 10)
    }

    func testHourlyAggregationOverflowRollsBackEventAndCheckpoint() throws {
        let store = try makeStore()
        try store.commit(ImportBatch(
            file: .fixture(committedOffset: 10),
            usageEvents: [.fixture(fingerprint: "usage-max", total: Int64.max)],
            quotaEvents: [],
            stateEvents: [],
            sessions: [],
            threadCheckpoints: []
        ))

        let overflowingBatch = ImportBatch(
            file: .fixture(committedOffset: 20),
            usageEvents: [.fixture(fingerprint: "usage-plus-one", total: 1)],
            quotaEvents: [],
            stateEvents: [],
            sessions: [],
            threadCheckpoints: []
        )

        XCTAssertThrowsError(try store.commit(overflowingBatch))
        XCTAssertEqual(try store.totalUsage(), Int64.max)
        XCTAssertEqual(try store.usageEventCount(), 1)
        XCTAssertEqual(try store.hourlyUsage().map(\.totalTokens), [Int64.max])
        XCTAssertEqual(try store.fileCheckpoint(fileID: overflowingBatch.file.fileID)?.committedOffset, 10)
    }

    func testUsageComponentSumOverflowIsRejectedBeforeWriting() throws {
        let store = try makeStore()
        let overflowingUsage = TokenUsageDelta(
            uncachedInput: Int64.max,
            cachedInput: 1,
            visibleOutput: 0,
            reasoning: 0
        )
        let batch = ImportBatch(
            file: .fixture(committedOffset: 10),
            usageEvents: [.fixture(fingerprint: "usage-component-overflow", usage: overflowingUsage)],
            quotaEvents: [],
            stateEvents: [],
            sessions: [],
            threadCheckpoints: []
        )

        XCTAssertThrowsError(try store.commit(batch))
        XCTAssertEqual(try store.usageEventCount(), 0)
        XCTAssertTrue(try store.hourlyUsage().isEmpty)
        XCTAssertNil(try store.fileCheckpoint(fileID: batch.file.fileID))
    }

    func testInvalidQuotaRemainingRollsBackEarlierUsageAndCheckpoint() throws {
        for invalidRemaining in [Double.nan, .infinity, -0.01, 1.01] {
            let store = try makeStore()
            let batch = ImportBatch(
                file: .fixture(committedOffset: 10),
                usageEvents: [.fixture(fingerprint: "usage-before-invalid-quota", total: 10)],
                quotaEvents: [.fixture(fingerprint: "quota-invalid", remaining: invalidRemaining)],
                stateEvents: [],
                sessions: [],
                threadCheckpoints: []
            )

            XCTAssertThrowsError(try store.commit(batch))
            XCTAssertEqual(try store.usageEventCount(), 0)
            XCTAssertEqual(try store.quotaEventCount(), 0)
            XCTAssertTrue(try store.hourlyUsage().isEmpty)
            XCTAssertNil(try store.fileCheckpoint(fileID: batch.file.fileID))
        }
    }

    func testSQLiteBindingCountMustExactlyMatchParameters() throws {
        let database = try SQLiteDatabase(url: temporaryDatabaseURL())

        XCTAssertThrowsError(try database.query(sql: "SELECT ? AS value"))
        XCTAssertThrowsError(try database.query(
            sql: "SELECT 1 AS value",
            bindings: [.integer(1)]
        ))
    }

    func testCorruptRequiredColumnTypeAndEnumAreReported() throws {
        let url = temporaryDatabaseURL()
        let store = try UsageStore(databaseURL: url)
        try store.commit(.fixture(session: .fixture(
            activity: .running,
            archive: .active,
            childEdgeStatus: nil
        )))
        let database = try SQLiteDatabase(url: url)

        try database.execute(
            sql: "UPDATE source_files SET committed_offset = 'not-an-integer' WHERE file_id = ?",
            bindings: [.text("file-1")]
        )
        XCTAssertThrowsError(try store.fileCheckpoint(fileID: "file-1"))

        try database.execute(
            sql: "UPDATE sessions SET activity_state = 'future-state' WHERE thread_id = ?",
            bindings: [.text("thread-1")]
        )
        XCTAssertThrowsError(try store.sessions())
    }

    private func makeStore() throws -> UsageStore {
        try UsageStore(databaseURL: temporaryDatabaseURL())
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SpendScope-UsageStoreTests-\(UUID().uuidString).sqlite3")
    }
}

private extension StoredUsageEvent {
    static func fixture(
        fingerprint: String,
        observedAtMilliseconds: Int64 = 3_600_001,
        threadID: String = "thread-1",
        total: Int64,
        project: ProjectIdentity = .unknown
    ) -> StoredUsageEvent {
        fixture(
            fingerprint: fingerprint,
            observedAtMilliseconds: observedAtMilliseconds,
            threadID: threadID,
            usage: TokenUsageDelta(
                uncachedInput: total,
                cachedInput: 0,
                visibleOutput: 0,
                reasoning: 0
            ),
            project: project
        )
    }

    static func fixture(
        fingerprint: String,
        observedAtMilliseconds: Int64 = 3_600_001,
        threadID: String = "thread-1",
        usage: TokenUsageDelta,
        project: ProjectIdentity = .unknown
    ) -> StoredUsageEvent {
        StoredUsageEvent(
            fingerprint: fingerprint,
            observedAtMilliseconds: observedAtMilliseconds,
            threadID: threadID,
            sourceKind: .cli,
            model: "test-model",
            plan: PlanResolver.resolve(rawValue: "plus"),
            usage: usage,
            sourceFileID: "file-1",
            sourceOffset: 64,
            project: project
        )
    }
}

private extension StoredQuotaEvent {
    static func fixture(
        fingerprint: String = "quota-1",
        kind: QuotaKind = .fiveHour,
        observedAtMilliseconds: Int64 = 2_000,
        remaining: Double = 0.75
    ) -> StoredQuotaEvent {
        StoredQuotaEvent(
            fingerprint: fingerprint,
            threadID: "thread-1",
            observation: QuotaObservation(
                kind: kind,
                observedAtMilliseconds: observedAtMilliseconds,
                windowMinutes: kind == .fiveHour ? 300 : 10_080,
                remaining: remaining,
                resetsAtMilliseconds: 3_000,
                plan: PlanResolver.resolve(rawValue: "plus")
            ),
            sourceKind: .cli
        )
    }
}

private extension StoredSessionStateEvent {
    static func fixture(fingerprint: String = "state-1") -> StoredSessionStateEvent {
        StoredSessionStateEvent(
            fingerprint: fingerprint,
            threadID: "thread-1",
            turnID: "turn-1",
            observedAtMilliseconds: 2_000,
            kind: .started,
            sourceFileID: "file-1",
            sourceOffset: 96
        )
    }
}

private extension StoredActivityEvent {
    static func fixture(
        fingerprint: String,
        observedAtMilliseconds: Int64,
        kind: ActivityKind,
        name: String
    ) -> StoredActivityEvent {
        StoredActivityEvent(
            fingerprint: fingerprint,
            observedAtMilliseconds: observedAtMilliseconds,
            threadID: "thread-1",
            turnID: "turn-1",
            kind: kind,
            name: name,
            sourceKind: .cli,
            sourceFileID: "file-1",
            sourceOffset: 120
        )
    }
}

private extension StoredSession {
    static func fixture(
        threadID: String = "thread-1",
        sourceFileID: String = "file-1",
        activity: SessionActivityState,
        archive: SessionArchiveState,
        childEdgeStatus: String?
    ) -> StoredSession {
        StoredSession(
            threadID: threadID,
            sourceKind: .cli,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            state: SessionStateSnapshot(
                threadID: threadID,
                activity: activity,
                archive: archive,
                childEdgeStatus: childEdgeStatus,
                activeTurnID: activity == .running ? "turn-1" : nil,
                lastActivityAtMilliseconds: 2_000,
                lastActivityEventKey: "file-1:96",
                archiveObservedAtMilliseconds: 2_000
            ),
            lastModel: "test-model",
            lastPlan: .plus,
            sourceFileID: sourceFileID
        )
    }
}

private extension FileCheckpoint {
    static func fixture(
        fileID: String = "file-1",
        committedOffset: Int64,
        threadID: String? = "thread-1",
        lastRecordAtMilliseconds: Int64? = 2_000,
        formatStatus: String = "supported",
        lastError: String? = nil,
        activityCommittedOffset: Int64 = 0
    ) -> FileCheckpoint {
        FileCheckpoint(
            fileID: fileID,
            deviceID: 11,
            inode: 22,
            path: "/synthetic/\(fileID).jsonl",
            fileSize: 200,
            committedOffset: committedOffset,
            generation: 0,
            threadID: threadID,
            lastRecordAtMilliseconds: lastRecordAtMilliseconds,
            lastSuccessAtMilliseconds: 3_000,
            formatStatus: formatStatus,
            lastError: lastError,
            activityCommittedOffset: activityCommittedOffset
        )
    }
}

private extension ThreadCheckpoint {
    static func fixture(counterSegment: Int64 = 1) -> ThreadCheckpoint {
        ThreadCheckpoint(
            threadID: "thread-1",
            currentModel: "test-model",
            currentPlan: PlanResolver.resolve(rawValue: "plus"),
            counters: TokenCounters(input: 100, cachedInput: 40, output: 20, reasoning: 5),
            counterSegment: counterSegment,
            lastTokenAtMilliseconds: 2_000
        )
    }
}

private extension ImportBatch {
    static func fixture(session: StoredSession) -> ImportBatch {
        ImportBatch(
            file: .fixture(committedOffset: 80),
            usageEvents: [],
            quotaEvents: [],
            stateEvents: [],
            sessions: [session],
            threadCheckpoints: []
        )
    }
}
