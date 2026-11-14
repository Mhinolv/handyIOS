import Foundation
import XCTest
@testable import HandyKit

final class RecoveryTests: XCTestCase {
    final class Clock: SessionClock {
        var now = Date(timeIntervalSince1970: 100)
    }

    func testFakeInterruptionAndRouteEventsNeverRestart() {
        XCTAssertEqual(CaptureRecoveryEvent.interruptionBegan.recovery, .interruption)
        XCTAssertNil(CaptureRecoveryEvent.interruptionEnded.recovery)
        XCTAssertNil(CaptureRecoveryEvent.routeChanged(microphoneAvailable: true).recovery)
        XCTAssertEqual(CaptureRecoveryEvent.routeChanged(microphoneAvailable: false).recovery, .route)
    }

    func testLaunchTimeoutAtFiveSeconds() throws {
        let clock = Clock()
        let session = DictationSession(storage: DictationSessionTests.Storage(), clock: clock)
        _ = try session.request()
        clock.now = clock.now.addingTimeInterval(4.99)
        XCTAssertNil(try session.checkLiveness())
        clock.now = clock.now.addingTimeInterval(0.01)
        XCTAssertEqual(try session.checkLiveness(), "Could not open handyIOS. Tap the mic to try again.")
        XCTAssertEqual(try session.snapshot().state, .idle)
    }

    func testHeartbeatAndRecoveryLiveness() throws {
        let clock = Clock()
        let session = DictationSession(storage: DictationSessionTests.Storage(), clock: clock)
        let id = try session.request().id
        _ = try session.startRecording(requestID: id)
        clock.now = clock.now.addingTimeInterval(4)
        try session.heartbeat(requestID: id)
        clock.now = clock.now.addingTimeInterval(4)
        XCTAssertNil(try session.checkLiveness())
        try session.recover(requestID: id, message: "Saved")
        clock.now = clock.now.addingTimeInterval(6)
        XCTAssertNil(try session.checkLiveness())
        XCTAssertTrue(try session.retry(requestID: id))
        try session.heartbeat(requestID: id)
        clock.now = clock.now.addingTimeInterval(5)
        XCTAssertEqual(try session.checkLiveness(), "handyIOS stopped. Tap the mic to try again.")
        XCTAssertFalse(try session.retry(requestID: id))
    }
}
