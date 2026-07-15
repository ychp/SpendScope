import XCTest
@testable import SpendScope

final class CodexEventDecoderTests: XCTestCase {
    private let decoder = CodexEventDecoder()

    func testDecodesDesktopSessionAndTurnModel() throws {
        let session = #"{"timestamp":"2026-07-14T06:55:00.000Z","type":"session_meta","payload":{"id":"thread-1","source":"vscode","originator":"Codex Desktop","cli_version":"0.144.4","model_provider":"openai"}}"#
        let turn = #"{"timestamp":"2026-07-14T06:55:01.000Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-5.6-sol"}}"#

        XCTAssertEqual(try decoder.decode(line: Data(session.utf8)), .session(.init(threadID: "thread-1", source: .desktop, formatVersion: "0.144.4")))
        XCTAssertEqual(try decoder.decode(line: Data(turn.utf8)), .turn(.init(turnID: "turn-1", model: "gpt-5.6-sol")))
    }

    func testSessionSourceObjectIsIgnoredWhileDesktopOriginatorRemainsAuthoritative() throws {
        let session = #"{"type":"session_meta","payload":{"id":"thread-object-desktop","source":{"subagent":true},"originator":"Codex Desktop","cli_version":"1.0.0"}}"#

        XCTAssertEqual(
            try decoder.decode(line: Data(session.utf8)),
            .session(.init(
                threadID: "thread-object-desktop",
                source: .desktop,
                formatVersion: "1.0.0"
            ))
        )
    }

    func testSessionStringCLISourceRemainsCLI() throws {
        let session = #"{"type":"session_meta","payload":{"id":"thread-cli","source":"cli","cli_version":"1.0.0"}}"#

        XCTAssertEqual(
            try decoder.decode(line: Data(session.utf8)),
            .session(.init(threadID: "thread-cli", source: .cli, formatVersion: "1.0.0"))
        )
    }

    func testSessionUnknownSourceObjectWithoutOriginatorMapsToUnknown() throws {
        let session = #"{"type":"session_meta","payload":{"id":"thread-object-unknown","source":{"subagent":true},"cli_version":"1.0.0"}}"#

        XCTAssertEqual(
            try decoder.decode(line: Data(session.utf8)),
            .session(.init(
                threadID: "thread-object-unknown",
                source: .unknown,
                formatVersion: "1.0.0"
            ))
        )
    }

    func testDecodesTokenCountersQuotasAndPlan() throws {
        let line = #"{"timestamp":"2026-07-14T06:55:23.433Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":32450,"cached_input_tokens":21248,"output_tokens":327,"reasoning_output_tokens":158,"total_tokens":32777}},"rate_limits":{"plan_type":"plus","primary":{"used_percent":15.0,"window_minutes":300,"resets_at":1784600433},"secondary":{"used_percent":16.0,"window_minutes":10080,"resets_at":1785200000}}}}"#

        guard case let .token(snapshot) = try decoder.decode(line: Data(line.utf8)) else {
            return XCTFail("Expected token event")
        }
        XCTAssertEqual(snapshot.counters, TokenCounters(input: 32_450, cachedInput: 21_248, output: 327, reasoning: 158))
        XCTAssertEqual(snapshot.planRaw, "plus")
        XCTAssertEqual(snapshot.quotas.map(\.windowMinutes), [300, 10_080])
    }

    func testDecodesOnlyWhitelistedLifecycleEventsAndIgnoresMessages() throws {
        let started = #"{"timestamp":"2026-07-14T06:55:02.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1","model_context_window":258400}}"#
        let message = #"{"timestamp":"2026-07-14T06:55:03.000Z","type":"event_msg","payload":{"type":"user_message","message":"must never enter the store"}}"#

        guard case let .lifecycle(event) = try decoder.decode(line: Data(started.utf8)) else {
            return XCTFail("Expected lifecycle event")
        }
        XCTAssertEqual(event.kind, .started)
        XCTAssertNil(try decoder.decode(line: Data(message.utf8)))
    }

    func testDecodesAllConfirmedLifecycleMappings() throws {
        let completed = #"{"timestamp":"2026-07-14T06:55:04.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-2"}}"#
        let interrupted = #"{"timestamp":"2026-07-14T06:55:05.000Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#
        let otherAbort = #"{"timestamp":"2026-07-14T06:55:06.000Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"replaced"}}"#
        let rolledBack = #"{"timestamp":"2026-07-14T06:55:07.000Z","type":"event_msg","payload":{"type":"thread_rolled_back"}}"#

        XCTAssertEqual(
            try decoder.decode(line: Data(completed.utf8)),
            .lifecycle(.init(kind: .completed, observedAtMilliseconds: 1_784_012_104_000, turnID: "turn-2"))
        )
        XCTAssertEqual(
            try decoder.decode(line: Data(interrupted.utf8)),
            .lifecycle(.init(kind: .interrupted, observedAtMilliseconds: 1_784_012_105_000, turnID: nil))
        )
        XCTAssertNil(try decoder.decode(line: Data(otherAbort.utf8)))
        XCTAssertEqual(
            try decoder.decode(line: Data(rolledBack.utf8)),
            .lifecycle(.init(kind: .rolledBack, observedAtMilliseconds: 1_784_012_107_000, turnID: nil))
        )
    }

    func testUnknownEventsIgnorePayloadShapeAndConflictingFields() throws {
        let unknownTopLevel = #"{"timestamp":"2026-07-14T06:55:08.000Z","type":"future_record","payload":"not-an-object"}"#
        let unknownMessage = #"{"timestamp":"2026-07-14T06:55:09.000Z","type":"event_msg","payload":{"type":"future_event","turn_id":42,"info":"not-an-object","rate_limits":false}}"#
        let message = #"{"timestamp":"2026-07-14T06:55:10.000Z","type":"event_msg","payload":{"type":"user_message","turn_id":42,"info":"not-an-object","rate_limits":false}}"#

        XCTAssertNil(try decoder.decode(line: Data(unknownTopLevel.utf8)))
        XCTAssertNil(try decoder.decode(line: Data(unknownMessage.utf8)))
        XCTAssertNil(try decoder.decode(line: Data(message.utf8)))
    }
}
