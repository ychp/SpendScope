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

    func testMigrationCreatesExactVersionOneStorageSurface() throws {
        let url = temporaryDatabaseURL()
        _ = try UsageStore(databaseURL: url)
        let store = try UsageStore(databaseURL: url)

        XCTAssertEqual(try store.schemaVersions(), [1])
        XCTAssertEqual(
            Set(try store.schemaColumns(table: "source_files")),
            Set([
                "file_id", "device_id", "inode", "path", "file_size", "committed_offset",
                "generation", "last_record_at_ms", "last_success_at_ms", "format_status", "last_error"
            ])
        )
        XCTAssertEqual(
            Set(try store.schemaTables()),
            Set([
                "schema_migrations", "source_files", "thread_checkpoints", "usage_events",
                "hourly_usage", "quota_snapshots", "session_state_events", "sessions", "source_status"
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
        XCTAssertEqual(try store.fileCheckpoint(fileID: batch.file.fileID)?.committedOffset, 160)
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

    private func makeStore() throws -> UsageStore {
        try UsageStore(databaseURL: temporaryDatabaseURL())
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SpendScope-UsageStoreTests-\(UUID().uuidString).sqlite3")
    }
}

private extension StoredUsageEvent {
    static func fixture(fingerprint: String, total: Int64) -> StoredUsageEvent {
        StoredUsageEvent(
            fingerprint: fingerprint,
            observedAtMilliseconds: 3_600_001,
            threadID: "thread-1",
            sourceKind: .cli,
            model: "test-model",
            plan: PlanResolver.resolve(rawValue: "plus"),
            usage: TokenUsageDelta(
                uncachedInput: total,
                cachedInput: 0,
                visibleOutput: 0,
                reasoning: 0
            ),
            sourceFileID: "file-1",
            sourceOffset: 64
        )
    }
}

private extension StoredQuotaEvent {
    static func fixture(fingerprint: String = "quota-1", remaining: Double = 0.75) -> StoredQuotaEvent {
        StoredQuotaEvent(
            fingerprint: fingerprint,
            threadID: "thread-1",
            observation: QuotaObservation(
                kind: .fiveHour,
                observedAtMilliseconds: 2_000,
                windowMinutes: 300,
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

private extension StoredSession {
    static func fixture(
        activity: SessionActivityState,
        archive: SessionArchiveState,
        childEdgeStatus: String?
    ) -> StoredSession {
        StoredSession(
            threadID: "thread-1",
            sourceKind: .cli,
            createdAtMilliseconds: 1_000,
            updatedAtMilliseconds: 2_000,
            state: SessionStateSnapshot(
                threadID: "thread-1",
                activity: activity,
                archive: archive,
                childEdgeStatus: childEdgeStatus,
                activeTurnID: activity == .running ? "turn-1" : nil,
                lastActivityAtMilliseconds: 2_000,
                lastActivityEventKey: "file-1:96",
                archiveObservedAtMilliseconds: archive == .archived ? 2_000 : nil
            ),
            lastModel: "test-model",
            lastPlan: .plus,
            sourceFileID: "file-1"
        )
    }
}

private extension FileCheckpoint {
    static func fixture(committedOffset: Int64) -> FileCheckpoint {
        FileCheckpoint(
            fileID: "file-1",
            deviceID: 11,
            inode: 22,
            path: "/synthetic/not-codex.jsonl",
            fileSize: 200,
            committedOffset: committedOffset,
            generation: 0,
            lastRecordAtMilliseconds: 2_000,
            lastSuccessAtMilliseconds: 3_000,
            formatStatus: "supported",
            lastError: nil
        )
    }
}

private extension ThreadCheckpoint {
    static func fixture(counterSegment: Int64 = 1) -> ThreadCheckpoint {
        ThreadCheckpoint(
            threadID: "thread-1",
            currentModel: "test-model",
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
