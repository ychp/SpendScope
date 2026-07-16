import Foundation

struct CodexEventDecoder {
    func isResponseItem(line: Data) -> Bool {
        (try? JSONDecoder().decode(TopLevelDiscriminator.self, from: line).type) == "response_item"
    }

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

        case "response_item":
            return try decodeResponseItem(line: line, decoder: decoder)

        default:
            return nil
        }
    }

    private func decodeResponseItem(
        line: Data,
        decoder: JSONDecoder
    ) throws -> CodexDecodedEvent? {
        let envelope = try decoder.decode(ResponseItemEnvelope.self, from: line)
        guard envelope.payload.type == "function_call"
                || envelope.payload.type == "custom_tool_call",
              let timestamp = envelope.timestamp,
              let name = envelope.payload.name,
              !name.isEmpty else {
            return nil
        }

        let input = envelope.payload.input ?? envelope.payload.arguments ?? ""
        let skillNames = ActivityCallScanner.skillNames(in: input)
        let toolNames: [String]
        if envelope.payload.type == "custom_tool_call", name == "exec" {
            let nestedNames = ActivityCallScanner.toolNames(in: input)
            toolNames = nestedNames.isEmpty ? [name] : nestedNames
        } else {
            toolNames = [name]
        }

        return .activity(.init(
            observedAtMilliseconds: try milliseconds(from: timestamp),
            callID: envelope.payload.callID,
            toolNames: toolNames,
            skillNames: skillNames
        ))
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

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            source = try? container.decode(String.self, forKey: .source)
            originator = try container.decodeIfPresent(String.self, forKey: .originator)
            cliVersion = try container.decodeIfPresent(String.self, forKey: .cliVersion)
        }

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

    struct ResponseItemEnvelope: Decodable {
        let timestamp: String?
        let payload: ResponseItemPayload
    }

    struct ResponseItemPayload: Decodable {
        let type: String
        let name: String?
        let input: String?
        let arguments: String?
        let callID: String?

        enum CodingKeys: String, CodingKey {
            case type
            case name
            case input
            case arguments
            case callID = "call_id"
        }
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

enum ActivityCallScanner {
    static func toolNames(in source: String) -> [String] {
        let searchable = codeRemovingStringsAndComments(source)
        guard let expression = try? NSRegularExpression(
            pattern: #"\btools\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\("#
        ) else {
            return []
        }
        let range = NSRange(searchable.startIndex..., in: searchable)
        return expression.matches(in: searchable, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: searchable) else { return nil }
            return String(searchable[swiftRange])
        }
    }

    static func skillNames(in source: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"/[^\s\"'`]+/SKILL\.md"#
        ) else {
            return []
        }
        let range = NSRange(source.startIndex..., in: source)
        let names = expression.matches(in: source, range: range).compactMap { match -> String? in
            guard let swiftRange = Range(match.range, in: source) else { return nil }
            return canonicalSkillName(path: String(source[swiftRange]))
        }
        return Array(Set(names)).sorted()
    }

    private static func canonicalSkillName(path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard components.last == "SKILL.md",
              let skillsIndex = components.lastIndex(of: "skills"),
              components.count >= 2 else {
            return nil
        }
        let skill = components[components.count - 2]
        guard skill != "SKILL.md", !skill.isEmpty else { return nil }

        if components.contains("plugins"),
           components.contains("cache"),
           skillsIndex >= 2 {
            let plugin = components[skillsIndex - 2]
            if !plugin.isEmpty, plugin != ".system" {
                return "\(plugin):\(skill)"
            }
        }
        return skill
    }

    private static func codeRemovingStringsAndComments(_ source: String) -> String {
        enum State {
            case code
            case singleQuoted
            case doubleQuoted
            case templateQuoted
            case lineComment
            case blockComment
        }

        let characters = Array(source)
        var result = Array(repeating: Character(" "), count: characters.count)
        var state = State.code
        var index = 0
        var escaped = false

        while index < characters.count {
            let current = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            switch state {
            case .code:
                if current == "/", next == "/" {
                    state = .lineComment
                    index += 2
                    continue
                }
                if current == "/", next == "*" {
                    state = .blockComment
                    index += 2
                    continue
                }
                if current == "'" {
                    state = .singleQuoted
                } else if current == "\"" {
                    state = .doubleQuoted
                } else if current == "`" {
                    state = .templateQuoted
                } else {
                    result[index] = current
                }

            case .singleQuoted, .doubleQuoted, .templateQuoted:
                if escaped {
                    escaped = false
                } else if current == "\\" {
                    escaped = true
                } else if (state == .singleQuoted && current == "'")
                            || (state == .doubleQuoted && current == "\"")
                            || (state == .templateQuoted && current == "`") {
                    state = .code
                }

            case .lineComment:
                if current == "\n" {
                    result[index] = current
                    state = .code
                }

            case .blockComment:
                if current == "*", next == "/" {
                    state = .code
                    index += 2
                    continue
                }
            }
            index += 1
        }
        return String(result)
    }
}
