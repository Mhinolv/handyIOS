import XCTest
@testable import HandyKit

final class ManualKeyboardStateTests: XCTestCase {
    private struct Clock {
        var now: Duration = .zero
        mutating func advance(_ duration: Duration) { now += duration }
    }

    func testRefreshPreservesPendingRequestStatus() {
        XCTAssertNil(KeyboardAccessStatus.message(fullAccess: true, manual: false, requestPending: true))
        XCTAssertNil(KeyboardAccessStatus.message(fullAccess: true, manual: true, requestPending: true))
        XCTAssertEqual(KeyboardAccessStatus.message(fullAccess: true, manual: false, requestPending: false),
                       "Tap the mic to dictate")
    }

    func testAccessGuidanceMatchesPanelAndOverridesPendingWhenDenied() {
        for pending in [false, true] {
            XCTAssertEqual(KeyboardAccessStatus.message(fullAccess: false, manual: true, requestPending: pending),
                           "Turn on Full Access in Settings to dictate.")
            XCTAssertEqual(KeyboardAccessStatus.message(fullAccess: false, manual: false, requestPending: pending),
                           "Turn on Full Access in Settings to dictate. Use ABC to type.")
        }
    }

    func testShiftIsOneShotAndCanBeCancelled() {
        var shift = ManualShiftState()
        XCTAssertEqual(shift.type("a"), "a")
        shift.toggle()
        XCTAssertEqual(shift.label(for: "z"), "Z")
        XCTAssertTrue(shift.isActive)
        XCTAssertEqual(shift.type("z"), "Z")
        XCTAssertFalse(shift.isActive)
        XCTAssertEqual(shift.type("b"), "b")
        shift.toggle()
        shift.toggle()
        XCTAssertEqual(shift.type("c"), "c")
    }

    func testDeleteIsImmediateThenRepeatsAtHoldBoundary() {
        var clock = Clock()
        var state = DeleteRepeatState()
        XCTAssertNil(state.delay(at: clock.now))
        XCTAssertTrue(state.press(at: clock.now), "Delete must fire on touch down")
        clock.advance(.milliseconds(399))
        XCTAssertFalse(state.tick(at: clock.now))
        XCTAssertEqual(state.delay(at: clock.now), .milliseconds(1))
        clock.advance(.milliseconds(1))
        XCTAssertTrue(state.tick(at: clock.now))
        clock.advance(.milliseconds(79))
        XCTAssertFalse(state.tick(at: clock.now))
        clock.advance(.milliseconds(1))
        XCTAssertTrue(state.tick(at: clock.now))
        state.release()
        clock.advance(.seconds(10))
        XCTAssertFalse(state.tick(at: clock.now))
        XCTAssertNil(state.delay(at: clock.now))
        XCTAssertTrue(state.press(at: clock.now))
        state.release()
        XCTAssertFalse(state.tick(at: clock.now + .seconds(1)))
    }

    func testLateTickDoesNotCatchUpAndNewPressRestartsDelay() {
        var state = DeleteRepeatState()
        _ = state.press(at: .zero)
        XCTAssertTrue(state.tick(at: .seconds(5)))
        XCTAssertFalse(state.tick(at: .seconds(5)))
        XCTAssertEqual(state.delay(at: .seconds(5)), .milliseconds(80))
        _ = state.press(at: .seconds(5))
        XCTAssertEqual(state.delay(at: .seconds(5)), .milliseconds(400))
    }
}
