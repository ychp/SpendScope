import XCTest
@testable import SpendScope

final class SessionStateReducerTests: XCTestCase {
    func testPreservesActivityAndArchiveAsIndependentFacts() {
        let started = SessionLifecycleEvent(kind: .started, observedAtMilliseconds: 100, turnID: "turn-1")
        let completed = SessionLifecycleEvent(kind: .completed, observedAtMilliseconds: 200, turnID: "turn-1")
        var state = SessionStateSnapshot.empty(threadID: "thread-1")

        state = SessionStateReducer.reduce(current: state, event: started, eventKey: "a:1")
        state = SessionStateReducer.reduce(current: state, event: completed, eventKey: "a:2")
        state = SessionStateReducer.setArchived(current: state, archived: true, observedAtMilliseconds: 300)

        XCTAssertEqual(state.activity, .completed)
        XCTAssertEqual(state.archive, .archived)
        XCTAssertEqual(state.displayState, .archived)
    }

    func testOlderEventsCannotOverwriteNewerStateAndOpenIsNotRunning() {
        var state = SessionStateSnapshot.empty(threadID: "thread-1")
        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .completed, observedAtMilliseconds: 200, turnID: "t"),
            eventKey: "b"
        )
        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .started, observedAtMilliseconds: 100, turnID: "t"),
            eventKey: "a"
        )
        state = SessionStateReducer.setChildEdgeStatus(current: state, status: "open")

        XCTAssertEqual(state.activity, .completed)
        XCTAssertEqual(state.childEdgeStatus, "open")
        XCTAssertNotEqual(state.displayState, .running)
    }

    func testLifecycleEventsUpdateActivityTurnAndOrderingMetadata() {
        var state = SessionStateSnapshot.empty(threadID: "thread-1")
        XCTAssertEqual(state.activity, .unknown)
        XCTAssertEqual(state.archive, .active)
        XCTAssertNil(state.activeTurnID)
        XCTAssertNil(state.lastActivityAtMilliseconds)
        XCTAssertNil(state.lastActivityEventKey)
        XCTAssertNil(state.archiveObservedAtMilliseconds)

        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .started, observedAtMilliseconds: 100, turnID: "turn-1"),
            eventKey: "file:10"
        )
        XCTAssertEqual(state.activity, .running)
        XCTAssertEqual(state.activeTurnID, "turn-1")
        XCTAssertEqual(state.lastActivityAtMilliseconds, 100)
        XCTAssertEqual(state.lastActivityEventKey, "file:10")

        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .interrupted, observedAtMilliseconds: 200, turnID: "turn-1"),
            eventKey: "file:20"
        )
        XCTAssertEqual(state.activity, .interrupted)
        XCTAssertNil(state.activeTurnID)

        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .started, observedAtMilliseconds: 300, turnID: "turn-2"),
            eventKey: "file:30"
        )
        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .rolledBack, observedAtMilliseconds: 400, turnID: nil),
            eventKey: "file:40"
        )
        XCTAssertEqual(state.activity, .rolledBack)
        XCTAssertNil(state.activeTurnID)
    }

    func testSameTimestampUsesLexicographicallyGreaterEventKey() {
        var state = SessionStateSnapshot.empty(threadID: "thread-1")
        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .completed, observedAtMilliseconds: 100, turnID: nil),
            eventKey: "b"
        )
        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .started, observedAtMilliseconds: 100, turnID: "ignored"),
            eventKey: "a"
        )
        XCTAssertEqual(state.activity, .completed)

        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .rolledBack, observedAtMilliseconds: 100, turnID: nil),
            eventKey: "c"
        )
        XCTAssertEqual(state.activity, .rolledBack)
        XCTAssertEqual(state.lastActivityEventKey, "c")
    }

    func testArchiveFactsRejectOlderUpdatesAndArchivedWinsAtSameTimestamp() {
        var state = SessionStateSnapshot.empty(threadID: "thread-1")
        state = SessionStateReducer.setArchived(current: state, archived: true, observedAtMilliseconds: 200)
        state = SessionStateReducer.setArchived(current: state, archived: false, observedAtMilliseconds: 100)
        XCTAssertEqual(state.archive, .archived)
        XCTAssertEqual(state.archiveObservedAtMilliseconds, 200)

        state = SessionStateReducer.setArchived(current: state, archived: false, observedAtMilliseconds: 300)
        XCTAssertEqual(state.archive, .active)

        state = SessionStateReducer.setArchived(current: state, archived: true, observedAtMilliseconds: 300)
        XCTAssertEqual(state.archive, .archived)

        state = SessionStateReducer.setArchived(current: state, archived: false, observedAtMilliseconds: 300)
        XCTAssertEqual(state.archive, .archived)
    }

    func testChildEdgeStatusDirectlyOverwritesWithoutChangingActivity() {
        var state = SessionStateSnapshot.empty(threadID: "thread-1")
        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .completed, observedAtMilliseconds: 100, turnID: nil),
            eventKey: "a"
        )
        state = SessionStateReducer.setChildEdgeStatus(current: state, status: "open")
        XCTAssertEqual(state.activity, .completed)
        XCTAssertEqual(state.childEdgeStatus, "open")

        state = SessionStateReducer.setChildEdgeStatus(current: state, status: nil)
        XCTAssertEqual(state.activity, .completed)
        XCTAssertNil(state.childEdgeStatus)
    }

    func testDisplayStateReflectsArchivedThenActivityPriority() {
        var state = SessionStateSnapshot.empty(threadID: "thread-1")
        XCTAssertEqual(state.displayState, .unknown)

        state = SessionStateReducer.reduce(
            current: state,
            event: .init(kind: .started, observedAtMilliseconds: 100, turnID: nil),
            eventKey: "a"
        )
        XCTAssertEqual(state.displayState, .running)

        state = SessionStateReducer.setArchived(current: state, archived: true, observedAtMilliseconds: 200)
        XCTAssertEqual(state.displayState, .archived)
    }
}
