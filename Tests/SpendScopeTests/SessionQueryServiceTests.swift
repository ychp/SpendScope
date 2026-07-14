import Foundation
import XCTest
@testable import SpendScope

final class SessionQueryServiceTests: XCTestCase {
    func testFiltersByDisplayStateAndUsesExactSourceCheckpointForFreshness() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.commit(batch(
            fileID: "session-file",
            lastRecordAtMilliseconds: 600_000,
            session: session(
                threadID: "abcdefgh-1234", sourceFileID: "session-file",
                activity: .running, archive: .active
            ),
            usage: usage(threadID: "abcdefgh-1234", total: 42)
        ))
        try store.commit(batch(
            fileID: "unrelated-file",
            lastRecordAtMilliseconds: 999_000,
            session: nil,
            usage: nil
        ))

        let rows = try SessionQueryService(store: store).sessions(
            filter: .init(displayStates: [.running]),
            now: now
        )

        XCTAssertEqual(rows.map(\.displayState), [.running])
        XCTAssertEqual(rows.map(\.freshness), [.stale])
        XCTAssertEqual(rows.map(\.shortThreadID), ["abcdefgh"])
        XCTAssertEqual(rows.map(\.totalTokens), [42])
    }

    func testRunningFreshnessThresholdAndMissingTimestampAreConservative() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.commit(batch(
            fileID: "fresh-file", lastRecordAtMilliseconds: 700_000,
            session: session(threadID: "fresh-thread", sourceFileID: "fresh-file", activity: .running),
            usage: nil
        ))
        try store.commit(batch(
            fileID: "unknown-file", lastRecordAtMilliseconds: nil,
            session: session(threadID: "unknown-thread", sourceFileID: "unknown-file", activity: .running),
            usage: nil
        ))

        let rows = try SessionQueryService(store: store).sessions(filter: .init(), now: now)

        XCTAssertEqual(rows.first { $0.shortThreadID == "fresh-th" }?.freshness, .fresh)
        XCTAssertEqual(rows.first { $0.shortThreadID == "unknown-" }?.freshness, .unknown)
    }

    func testFiltersOrthogonalFactsAndDerivesArchivedDisplayPriority() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try makeStore()
        try store.commit(batch(
            fileID: "archived-file", lastRecordAtMilliseconds: 900_000,
            session: session(
                threadID: "archived-thread", sourceFileID: "archived-file",
                source: .desktop, activity: .completed, archive: .archived,
                model: "gpt-test", plan: .plus, updatedAtMilliseconds: 800_000
            ),
            usage: usage(threadID: "archived-thread", total: 99)
        ))
        try store.commit(batch(
            fileID: "active-file", lastRecordAtMilliseconds: 950_000,
            session: session(
                threadID: "active-thread", sourceFileID: "active-file",
                source: .desktop, activity: .completed, archive: .active,
                model: "gpt-test", plan: .plus, updatedAtMilliseconds: 900_000
            ),
            usage: nil
        ))

        let rows = try SessionQueryService(store: store).sessions(
            filter: .init(
                displayStates: [.archived], activities: [.completed], archives: [.archived],
                sources: [.desktop], models: ["gpt-test"], plans: [.plus],
                updatedAfterMilliseconds: 700_000
            ),
            now: now
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.displayState, .archived)
        XCTAssertEqual(rows.first?.source, .desktop)
        XCTAssertEqual(rows.first?.model, "gpt-test")
        XCTAssertEqual(rows.first?.plan, .plus)
        XCTAssertEqual(rows.first?.totalTokens, 99)
    }

    private func makeStore() throws -> UsageStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionQueryServiceTests-\(UUID().uuidString).sqlite3")
        return try UsageStore(databaseURL: url)
    }

    private func session(
        threadID: String,
        sourceFileID: String,
        source: CodexSourceKind = .cli,
        activity: SessionActivityState,
        archive: SessionArchiveState = .active,
        model: String = "test-model",
        plan: PlanKind = .free,
        updatedAtMilliseconds: Int64 = 800_000
    ) -> StoredSession {
        StoredSession(
            threadID: threadID,
            sourceKind: source,
            createdAtMilliseconds: 100_000,
            updatedAtMilliseconds: updatedAtMilliseconds,
            state: SessionStateSnapshot(
                threadID: threadID, activity: activity, archive: archive,
                childEdgeStatus: nil,
                activeTurnID: activity == .running ? "turn-1" : nil,
                lastActivityAtMilliseconds: updatedAtMilliseconds,
                lastActivityEventKey: "\(sourceFileID):1",
                archiveObservedAtMilliseconds: archive == .archived ? updatedAtMilliseconds : nil
            ),
            lastModel: model,
            lastPlan: plan,
            sourceFileID: sourceFileID
        )
    }

    private func usage(threadID: String, total: Int64) -> StoredUsageEvent {
        StoredUsageEvent(
            fingerprint: "usage-\(threadID)", observedAtMilliseconds: 500_000,
            threadID: threadID, sourceKind: .cli, model: "test-model",
            plan: PlanResolver.resolve(rawValue: "free"),
            usage: .init(uncachedInput: total, cachedInput: 0, visibleOutput: 0, reasoning: 0),
            sourceFileID: "usage-file", sourceOffset: 1
        )
    }

    private func batch(
        fileID: String,
        lastRecordAtMilliseconds: Int64?,
        session: StoredSession?,
        usage: StoredUsageEvent?
    ) -> ImportBatch {
        ImportBatch(
            file: FileCheckpoint(
                fileID: fileID, deviceID: 1, inode: Int64(fileID.hashValue),
                path: "/synthetic/\(fileID).jsonl", fileSize: 10, committedOffset: 10,
                generation: 0, threadID: session?.threadID,
                lastRecordAtMilliseconds: lastRecordAtMilliseconds,
                lastSuccessAtMilliseconds: nil, formatStatus: "supported", lastError: nil
            ),
            usageEvents: usage.map { [$0] } ?? [], quotaEvents: [], stateEvents: [],
            sessions: session.map { [$0] } ?? [], threadCheckpoints: []
        )
    }
}
