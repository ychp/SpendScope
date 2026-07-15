enum SessionActivityState: String, Codable, Sendable {
    case running
    case completed
    case interrupted
    case rolledBack
    case unknown
}

enum SessionArchiveState: String, Codable, Sendable {
    case active
    case archived
}

enum SessionDisplayState: String, Codable, Sendable {
    case archived
    case running
    case interrupted
    case rolledBack
    case completed
    case unknown
}

struct SessionStateSnapshot: Equatable, Sendable {
    let threadID: String
    let activity: SessionActivityState
    let archive: SessionArchiveState
    let childEdgeStatus: String?
    let activeTurnID: String?
    let lastActivityAtMilliseconds: Int64?
    let lastActivityEventKey: String?
    let archiveObservedAtMilliseconds: Int64?

    var displayState: SessionDisplayState {
        if archive == .archived {
            return .archived
        }

        switch activity {
        case .running:
            return .running
        case .interrupted:
            return .interrupted
        case .rolledBack:
            return .rolledBack
        case .completed:
            return .completed
        case .unknown:
            return .unknown
        }
    }

    static func empty(threadID: String) -> SessionStateSnapshot {
        SessionStateSnapshot(
            threadID: threadID,
            activity: .unknown,
            archive: .active,
            childEdgeStatus: nil,
            activeTurnID: nil,
            lastActivityAtMilliseconds: nil,
            lastActivityEventKey: nil,
            archiveObservedAtMilliseconds: nil
        )
    }
}

enum SessionStateReducer {
    static func reduce(
        current: SessionStateSnapshot,
        event: SessionLifecycleEvent,
        eventKey: String
    ) -> SessionStateSnapshot {
        guard isNewerActivity(
            eventMilliseconds: event.observedAtMilliseconds,
            eventKey: eventKey,
            than: current
        ) else {
            return current
        }

        let activity: SessionActivityState
        let activeTurnID: String?
        switch event.kind {
        case .started:
            activity = .running
            activeTurnID = event.turnID
        case .completed:
            activity = .completed
            activeTurnID = nil
        case .interrupted:
            activity = .interrupted
            activeTurnID = nil
        case .rolledBack:
            activity = .rolledBack
            activeTurnID = nil
        }

        return SessionStateSnapshot(
            threadID: current.threadID,
            activity: activity,
            archive: current.archive,
            childEdgeStatus: current.childEdgeStatus,
            activeTurnID: activeTurnID,
            lastActivityAtMilliseconds: event.observedAtMilliseconds,
            lastActivityEventKey: eventKey,
            archiveObservedAtMilliseconds: current.archiveObservedAtMilliseconds
        )
    }

    static func setArchived(
        current: SessionStateSnapshot,
        archived: Bool,
        observedAtMilliseconds: Int64
    ) -> SessionStateSnapshot {
        if let currentObservedAt = current.archiveObservedAtMilliseconds {
            if observedAtMilliseconds < currentObservedAt {
                return current
            }
            if observedAtMilliseconds == currentObservedAt,
               current.archive == .archived,
               !archived {
                return current
            }
        }

        return SessionStateSnapshot(
            threadID: current.threadID,
            activity: current.activity,
            archive: archived ? .archived : .active,
            childEdgeStatus: current.childEdgeStatus,
            activeTurnID: current.activeTurnID,
            lastActivityAtMilliseconds: current.lastActivityAtMilliseconds,
            lastActivityEventKey: current.lastActivityEventKey,
            archiveObservedAtMilliseconds: observedAtMilliseconds
        )
    }

    static func setChildEdgeStatus(
        current: SessionStateSnapshot,
        status: String?
    ) -> SessionStateSnapshot {
        SessionStateSnapshot(
            threadID: current.threadID,
            activity: current.activity,
            archive: current.archive,
            childEdgeStatus: status,
            activeTurnID: current.activeTurnID,
            lastActivityAtMilliseconds: current.lastActivityAtMilliseconds,
            lastActivityEventKey: current.lastActivityEventKey,
            archiveObservedAtMilliseconds: current.archiveObservedAtMilliseconds
        )
    }

    private static func isNewerActivity(
        eventMilliseconds: Int64,
        eventKey: String,
        than current: SessionStateSnapshot
    ) -> Bool {
        guard let currentMilliseconds = current.lastActivityAtMilliseconds,
              let currentEventKey = current.lastActivityEventKey else {
            return true
        }

        if eventMilliseconds != currentMilliseconds {
            return eventMilliseconds > currentMilliseconds
        }
        return eventKey > currentEventKey
    }
}
