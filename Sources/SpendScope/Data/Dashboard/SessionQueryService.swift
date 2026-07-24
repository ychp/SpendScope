import CryptoKit
import Foundation

struct SessionFilter: Sendable {
    let displayStates: Set<SessionDisplayState>
    let activities: Set<SessionActivityState>
    let archives: Set<SessionArchiveState>
    let sources: Set<CodexSourceKind>
    let models: Set<String>
    let plans: Set<PlanKind>
    let updatedAfterMilliseconds: Int64?
    let updatedBeforeMilliseconds: Int64?

    init(
        displayStates: Set<SessionDisplayState> = [],
        activities: Set<SessionActivityState> = [],
        archives: Set<SessionArchiveState> = [],
        sources: Set<CodexSourceKind> = [],
        models: Set<String> = [],
        plans: Set<PlanKind> = [],
        updatedAfterMilliseconds: Int64? = nil,
        updatedBeforeMilliseconds: Int64? = nil
    ) {
        self.displayStates = displayStates
        self.activities = activities
        self.archives = archives
        self.sources = sources
        self.models = models
        self.plans = plans
        self.updatedAfterMilliseconds = updatedAfterMilliseconds
        self.updatedBeforeMilliseconds = updatedBeforeMilliseconds
    }
}

enum SessionFreshness: String, Sendable {
    case fresh
    case stale
    case unknown
}

struct SessionSummary: Sendable {
    let shortThreadID: String
    let createdAtMilliseconds: Int64?
    let updatedAtMilliseconds: Int64?
    let source: CodexSourceKind
    let model: String
    let plan: PlanKind
    let displayState: SessionDisplayState
    let freshness: SessionFreshness
    let totalTokens: Int64
}

final class SessionQueryService: @unchecked Sendable {
    private static let staleIntervalMilliseconds: Int64 = 5 * 60 * 1_000
    private let store: UsageStore

    init(store: UsageStore) {
        self.store = store
    }

    func sessions(filter: SessionFilter, now: Date) throws -> [SessionSummary] {
        let nowMilliseconds = Int64((now.timeIntervalSince1970 * 1_000).rounded(.towardZero))
        return try store.sessionQueryRows()
            .filter { matches($0, filter: filter) }
            .sorted { left, right in
                let leftUpdated = left.session.updatedAtMilliseconds ?? Int64.min
                let rightUpdated = right.session.updatedAtMilliseconds ?? Int64.min
                if leftUpdated != rightUpdated { return leftUpdated > rightUpdated }
                return left.session.threadID < right.session.threadID
            }
            .map { row in
                let session = row.session
                return SessionSummary(
                    shortThreadID: ThreadDisplayIdentifier.make(from: session.threadID),
                    createdAtMilliseconds: session.createdAtMilliseconds,
                    updatedAtMilliseconds: session.updatedAtMilliseconds,
                    source: session.sourceKind,
                    model: session.lastModel ?? "Unknown Model",
                    plan: session.lastPlan ?? .free,
                    displayState: session.state.displayState,
                    freshness: freshness(
                        activity: session.activity,
                        lastRecordAtMilliseconds: row.sourceLastRecordAtMilliseconds,
                        nowMilliseconds: nowMilliseconds
                    ),
                    totalTokens: row.totalTokens
                )
            }
    }

    private func matches(_ row: StoredSessionQueryRow, filter: SessionFilter) -> Bool {
        let session = row.session
        let model = session.lastModel ?? "Unknown Model"
        let plan = session.lastPlan ?? .free
        guard filter.displayStates.isEmpty || filter.displayStates.contains(session.state.displayState),
              filter.activities.isEmpty || filter.activities.contains(session.activity),
              filter.archives.isEmpty || filter.archives.contains(session.archive),
              filter.sources.isEmpty || filter.sources.contains(session.sourceKind),
              filter.models.isEmpty || filter.models.contains(model),
              filter.plans.isEmpty || filter.plans.contains(plan) else {
            return false
        }
        if let after = filter.updatedAfterMilliseconds {
            guard let updated = session.updatedAtMilliseconds, updated >= after else { return false }
        }
        if let before = filter.updatedBeforeMilliseconds {
            guard let updated = session.updatedAtMilliseconds, updated <= before else { return false }
        }
        return true
    }

    private func freshness(
        activity: SessionActivityState,
        lastRecordAtMilliseconds: Int64?,
        nowMilliseconds: Int64
    ) -> SessionFreshness {
        guard activity == .running, let lastRecordAtMilliseconds else { return .unknown }
        guard nowMilliseconds > lastRecordAtMilliseconds else { return .fresh }
        let (age, overflow) = nowMilliseconds.subtractingReportingOverflow(lastRecordAtMilliseconds)
        return overflow || age > Self.staleIntervalMilliseconds ? .stale : .fresh
    }
}

enum ThreadDisplayIdentifier {
    static func make(from threadID: String) -> String {
        let digest = SHA256.hash(data: Data(threadID.utf8))
        let prefix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "thread-\(prefix)"
    }
}
