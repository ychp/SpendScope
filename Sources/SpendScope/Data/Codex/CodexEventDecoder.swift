import Foundation

struct CodexEventDecoder {
    func decode(line: Data) throws -> CodexDecodedEvent? {
        let envelope = try JSONDecoder().decode(Envelope.self, from: line)

        switch envelope.type {
        case "session_meta":
            guard
                let threadID = envelope.payload.id,
                let formatVersion = envelope.payload.cliVersion
            else {
                return nil
            }

            let source: CodexSourceKind
            if envelope.payload.originator == "Codex Desktop" {
                source = .desktop
            } else if envelope.payload.source == "cli" {
                source = .cli
            } else {
                source = .unknown
            }
            return .session(.init(threadID: threadID, source: source, formatVersion: formatVersion))

        case "turn_context":
            guard
                let turnID = envelope.payload.turnID,
                let model = envelope.payload.model
            else {
                return nil
            }
            return .turn(.init(turnID: turnID, model: model))

        case "event_msg":
            return try decodeEventMessage(envelope)

        default:
            return nil
        }
    }

    private func decodeEventMessage(_ envelope: Envelope) throws -> CodexDecodedEvent? {
        guard let eventType = envelope.payload.type else {
            return nil
        }

        switch eventType {
        case "token_count":
            let counters = envelope.payload.info?.totalTokenUsage.map {
                TokenCounters(
                    input: $0.inputTokens,
                    cachedInput: $0.cachedInputTokens,
                    output: $0.outputTokens,
                    reasoning: $0.reasoningOutputTokens
                )
            }
            let rateLimits = envelope.payload.rateLimits
            let quotas = [rateLimits?.primary, rateLimits?.secondary]
                .compactMap { $0 }
                .map {
                    RawQuotaWindow(
                        windowMinutes: $0.windowMinutes,
                        usedPercent: $0.usedPercent,
                        resetsAtSeconds: $0.resetsAt
                    )
                }
            return .token(
                .init(
                    observedAtMilliseconds: try milliseconds(from: envelope.timestamp),
                    counters: counters,
                    planRaw: rateLimits?.planType,
                    quotas: quotas
                )
            )

        case "task_started":
            return try lifecycle(.started, envelope: envelope)

        case "task_complete":
            return try lifecycle(.completed, envelope: envelope)

        case "turn_aborted" where envelope.payload.reason == "interrupted":
            return try lifecycle(.interrupted, envelope: envelope)

        case "thread_rolled_back":
            return try lifecycle(.rolledBack, envelope: envelope)

        default:
            return nil
        }
    }

    private func lifecycle(
        _ kind: SessionLifecycleKind,
        envelope: Envelope
    ) throws -> CodexDecodedEvent {
        .lifecycle(
            .init(
                kind: kind,
                observedAtMilliseconds: try milliseconds(from: envelope.timestamp),
                turnID: envelope.payload.turnID
            )
        )
    }

    private func milliseconds(from timestamp: String) throws -> Int64 {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: timestamp) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Invalid fractional ISO-8601 timestamp")
            )
        }
        return Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

private extension CodexEventDecoder {
    struct Envelope: Decodable {
        let timestamp: String
        let type: String
        let payload: Payload
    }

    struct Payload: Decodable {
        let id: String?
        let source: String?
        let originator: String?
        let cliVersion: String?
        let turnID: String?
        let model: String?
        let type: String?
        let info: TokenInfo?
        let rateLimits: RateLimits?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case originator
            case cliVersion = "cli_version"
            case turnID = "turn_id"
            case model
            case type
            case info
            case rateLimits = "rate_limits"
            case reason
        }
    }

    struct TokenInfo: Decodable {
        let totalTokenUsage: TotalTokenUsage?

        enum CodingKeys: String, CodingKey {
            case totalTokenUsage = "total_token_usage"
        }
    }

    struct TotalTokenUsage: Decodable {
        let inputTokens: Int64
        let cachedInputTokens: Int64
        let outputTokens: Int64
        let reasoningOutputTokens: Int64

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
            case reasoningOutputTokens = "reasoning_output_tokens"
        }
    }

    struct RateLimits: Decodable {
        let planType: String?
        let primary: QuotaWindow?
        let secondary: QuotaWindow?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case primary
            case secondary
        }
    }

    struct QuotaWindow: Decodable {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: Int64?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }
    }
}
