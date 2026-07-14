import Foundation

struct CodexEventDecoder {
    func decode(line: Data) throws -> CodexDecodedEvent? {
        let decoder = JSONDecoder()
        let discriminator = try decoder.decode(TopLevelDiscriminator.self, from: line)

        switch discriminator.type {
        case "session_meta":
            let envelope = try decoder.decode(SessionEnvelope.self, from: line)
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
            return .session(
                .init(
                    threadID: threadID,
                    source: source,
                    formatVersion: formatVersion
                )
            )

        case "turn_context":
            let envelope = try decoder.decode(TurnEnvelope.self, from: line)
            guard
                let turnID = envelope.payload.turnID,
                let model = envelope.payload.model
            else {
                return nil
            }
            return .turn(.init(turnID: turnID, model: model))

        case "event_msg":
            let eventDiscriminator = try decoder.decode(EventDiscriminatorEnvelope.self, from: line)
            return try decodeEventMessage(
                line: line,
                eventType: eventDiscriminator.payload.type,
                decoder: decoder
            )

        default:
            return nil
        }
    }

    private func decodeEventMessage(
        line: Data,
        eventType: String,
        decoder: JSONDecoder
    ) throws -> CodexDecodedEvent? {
        switch eventType {
        case "token_count":
            let envelope = try decoder.decode(TokenEnvelope.self, from: line)
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
            return try lifecycle(.started, line: line, decoder: decoder)

        case "task_complete":
            return try lifecycle(.completed, line: line, decoder: decoder)

        case "turn_aborted":
            let envelope = try decoder.decode(LifecycleEnvelope.self, from: line)
            guard envelope.payload.reason == "interrupted" else {
                return nil
            }
            return try lifecycle(.interrupted, envelope: envelope)

        case "thread_rolled_back":
            return try lifecycle(.rolledBack, line: line, decoder: decoder)

        default:
            return nil
        }
    }

    private func lifecycle(
        _ kind: SessionLifecycleKind,
        line: Data,
        decoder: JSONDecoder
    ) throws -> CodexDecodedEvent {
        try lifecycle(kind, envelope: decoder.decode(LifecycleEnvelope.self, from: line))
    }

    private func lifecycle(
        _ kind: SessionLifecycleKind,
        envelope: LifecycleEnvelope
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
    struct TopLevelDiscriminator: Decodable {
        let type: String
    }

    struct EventDiscriminatorEnvelope: Decodable {
        let payload: EventDiscriminator
    }

    struct EventDiscriminator: Decodable {
        let type: String
    }

    struct SessionEnvelope: Decodable {
        let payload: SessionPayload
    }

    struct SessionPayload: Decodable {
        let id: String?
        let source: String?
        let originator: String?
        let cliVersion: String?

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case originator
            case cliVersion = "cli_version"
        }
    }

    struct TurnEnvelope: Decodable {
        let payload: TurnPayload
    }

    struct TurnPayload: Decodable {
        let turnID: String?
        let model: String?

        enum CodingKeys: String, CodingKey {
            case turnID = "turn_id"
            case model
        }
    }

    struct TokenEnvelope: Decodable {
        let timestamp: String
        let payload: TokenPayload
    }

    struct TokenPayload: Decodable {
        let info: TokenInfo?
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case info
            case rateLimits = "rate_limits"
        }
    }

    struct LifecycleEnvelope: Decodable {
        let timestamp: String
        let payload: LifecyclePayload
    }

    struct LifecyclePayload: Decodable {
        let turnID: String?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case turnID = "turn_id"
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
