import Foundation
import XCTest
@testable import HandyKit

/// #38: the keyboard opened Handy while Handy was in front. The first controller never
/// started, and each later request was refused or cancelled the capture at once.
final class HandoffRouterTests: XCTestCase {
    private typealias Storage = DictationSessionTests.Storage

    // Device log 07:23:02-07:23:10: four mic taps, the first controller is stale.
    func testNewRequestReplacesStaleControllerAfterRepeatedTaps() throws {
        let clock = DictationSessionTests.Clock()
        let storage = Storage()
        let keyboard = DictationSession(storage: storage, clock: clock)
        let first = try keyboard.request()
        var current: HandoffController? = nil
        XCTAssertEqual(HandoffRouter.decide(requestID: first.id, current: current,
                                            snapshot: try keyboard.snapshot()), .start)
        // The cover did not present, so the controller never started.
        current = HandoffController(id: first.id, state: .idle)
        // Taps 2 and 3 reuse the same request and must not make a second controller.
        XCTAssertEqual(KeyboardTapRule.action(for: try keyboard.snapshot()), .open(first.id))
        XCTAssertEqual(HandoffRouter.decide(requestID: first.id, current: current,
                                            snapshot: try keyboard.snapshot()), .ignoreDuplicate)
        // The keyboard liveness check clears the stale request after 5 seconds.
        clock.now.addTimeInterval(5)
        XCTAssertNotNil(try keyboard.checkLiveness())
        // Tap 4 makes a new request. The app must follow it, not keep the stale one.
        XCTAssertEqual(KeyboardTapRule.action(for: try keyboard.snapshot()), .newRequest)
        let second = try keyboard.request()
        XCTAssertEqual(HandoffRouter.decide(requestID: second.id, current: current,
                                            snapshot: try keyboard.snapshot()),
                       .replace(previous: first.id))
        // The new controller then owns the slot, so startRecording succeeds.
        XCTAssertTrue(try DictationSession(storage: storage, clock: clock).startRecording(requestID: second.id))
    }

    // The stale controller's startRecording returns false. Its cancel must not clear the new request.
    func testStaleControllerCancelKeepsNewRequest() throws {
        let storage = Storage()
        let keyboard = DictationSession(storage: storage)
        let app = DictationSession(storage: storage)
        let stale = try keyboard.request()
        XCTAssertTrue(try keyboard.cancel(requestID: stale.id))
        let live = try keyboard.request()
        XCTAssertFalse(try app.startRecording(requestID: stale.id))
        XCTAssertFalse(try app.cancel(requestID: stale.id))
        XCTAssertEqual(try app.snapshot().request?.id, live.id)
        XCTAssertEqual(try app.snapshot().state, .requested)
    }

    // The heartbeat compares the slot id with its own id. A new request means the old one is over.
    func testHeartbeatMismatchOnlyAfterReplacement() throws {
        let storage = Storage()
        let session = DictationSession(storage: storage)
        let request = try session.request()
        XCTAssertTrue(try session.startRecording(requestID: request.id))
        try session.heartbeat(requestID: request.id)
        XCTAssertEqual(try session.snapshot().request?.id, request.id)
        // A second tap while recording asks for a stop. It does not make a new request.
        XCTAssertEqual(KeyboardTapRule.action(for: try session.snapshot()), .stop(request.id))
        XCTAssertThrowsError(try session.request())
    }

    func testActiveControllerIsNotReplaced() throws {
        let session = DictationSession(storage: Storage())
        let request = try session.request()
        let other = UUID()
        for state in [MicrophoneSession.State.askingPermission, .recording, .stopped] {
            XCTAssertEqual(HandoffRouter.decide(requestID: request.id,
                current: HandoffController(id: request.id, state: state),
                snapshot: try session.snapshot()), .ignoreDuplicate)
            XCTAssertEqual(HandoffRouter.decide(requestID: other,
                current: HandoffController(id: request.id, state: state),
                snapshot: try session.snapshot()), .unavailable(reason: "request not in slot"))
        }
    }

    func testFinishedControllerWithSameIDStartsAgainOnlyIfRequested() throws {
        let session = DictationSession(storage: Storage())
        let request = try session.request()
        XCTAssertEqual(HandoffRouter.decide(requestID: request.id,
            current: HandoffController(id: request.id, state: .cancelled),
            snapshot: try session.snapshot()), .replace(previous: request.id))
    }

    func testFailedRequestAfterRestartReportsLostAudio() throws {
        let session = DictationSession(storage: Storage())
        let request = try session.request()
        XCTAssertTrue(try session.fail(requestID: request.id))
        XCTAssertEqual(HandoffRouter.decide(requestID: request.id, current: nil,
                                            snapshot: try session.snapshot()), .savedAudioLost)
        XCTAssertEqual(HandoffRouter.decide(requestID: UUID(), current: nil,
                                            snapshot: try session.snapshot()),
                       .unavailable(reason: "request not in slot"))
    }

    func testRecordingRequestIsNotStartedTwice() throws {
        let session = DictationSession(storage: Storage())
        let request = try session.request()
        XCTAssertTrue(try session.startRecording(requestID: request.id))
        XCTAssertEqual(HandoffRouter.decide(requestID: request.id, current: nil,
                                            snapshot: try session.snapshot()),
                       .unavailable(reason: "slot state recording"))
    }

    // Owner report: "I kept on seeing a message to open the handy app, even though I was already inside of it."
    func testKeyboardDoesNotAskToOpenHandyWhenHandyIsInFrontOrRecording() {
        XCTAssertNil(KeyboardRequestStatus.afterOpen(appInFront: true))
        XCTAssertEqual(KeyboardRequestStatus.afterOpen(appInFront: false), "Open Handy, then come back.")
        XCTAssertNil(KeyboardRequestStatus.resumed(state: .recording, appInFront: false))
        XCTAssertNil(KeyboardRequestStatus.resumed(state: .transcribing, appInFront: false))
        XCTAssertNil(KeyboardRequestStatus.resumed(state: .requested, appInFront: true))
        XCTAssertEqual(KeyboardRequestStatus.resumed(state: .requested, appInFront: false),
                       "Open Handy, then come back.")
    }

    func testAppPresenceExpires() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(AppPresence.isInFront(activeAt: now.addingTimeInterval(-2), now: now))
        XCTAssertFalse(AppPresence.isInFront(activeAt: now.addingTimeInterval(-AppPresence.lifetime), now: now))
        XCTAssertFalse(AppPresence.isInFront(activeAt: nil, now: now))
    }
}

final class AppPresenceDefaultsTests: XCTestCase {
    func testMarkAndClear() throws {
        let name = "AppPresenceDefaultsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date(timeIntervalSince1970: 5000)
        XCTAssertFalse(AppPresence.isInFront(defaults, now: now))
        AppPresence.markActive(defaults, now: now)
        XCTAssertTrue(AppPresence.isInFront(defaults, now: now.addingTimeInterval(1)))
        XCTAssertFalse(AppPresence.isInFront(defaults, now: now.addingTimeInterval(10)))
        AppPresence.clear(defaults)
        XCTAssertFalse(AppPresence.isInFront(defaults, now: now))
    }
}
