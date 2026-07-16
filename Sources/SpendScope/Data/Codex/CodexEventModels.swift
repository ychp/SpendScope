import CryptoKit
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

struct ProjectIdentity: Equatable, Sendable {
    let id: String
    let name: String

    static let unknown = ProjectIdentity(id: "unknown", name: "未识别项目")

    static func resolve(cwd: String?) -> ProjectIdentity? {
        guard let cwd = cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty else { return nil }
        let standardizedPath = URL(fileURLWithPath: cwd).standardizedFileURL.path
        let name = URL(fileURLWithPath: standardizedPath).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "/" else { return nil }
        let id = SHA256.hash(data: Data(standardizedPath.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return ProjectIdentity(id: id, name: name)
    }
}

struct SessionMetadata: Equatable, Sendable {
    let threadID: String
    let source: CodexSourceKind
    let formatVersion: String
    let project: ProjectIdentity?

    init(
        threadID: String,
        source: CodexSourceKind,
        formatVersion: String,
        project: ProjectIdentity? = nil
    ) {
        self.threadID = threadID
        self.source = source
        self.formatVersion = formatVersion
        self.project = project
    }
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

enum ActivityKind: String, Codable, Sendable {
    case skill
    case tool
}

struct ActivityCallSnapshot: Equatable, Sendable {
    let observedAtMilliseconds: Int64
    let callID: String?
    let toolNames: [String]
    let skillNames: [String]
}

enum CodexDecodedEvent: Equatable, Sendable {
    case session(SessionMetadata)
    case turn(TurnContext)
    case token(TokenCounterSnapshot)
    case lifecycle(SessionLifecycleEvent)
    case activity(ActivityCallSnapshot)
}
