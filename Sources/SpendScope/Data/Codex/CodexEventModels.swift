import Foundation

enum CodexSourceKind: String, Codable, Sendable {
    case cli
    case desktop
    case unknown
}

enum PlanKind: String, Codable, Sendable {
    case free
    case plus
    case proLite
    case pro20x
}

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
    case started
    case completed
    case interrupted
    case rolledBack
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
