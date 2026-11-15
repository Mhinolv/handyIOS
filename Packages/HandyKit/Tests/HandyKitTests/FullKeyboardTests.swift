import XCTest
@testable import HandyKit

final class FullKeyboardTests: XCTestCase {
    func testEveryLayerTypesAllKeysAndStaysSelected() {
        var state = ManualKeyboardState()
        for layer in ManualKeyboardLayer.allCases {
            state.select(layer)
            for character in layer.rows.joined() {
                XCTAssertEqual(state.type(String(character)), String(character))
                XCTAssertEqual(state.layer, layer)
            }
            XCTAssertEqual(layer.rows.count, 3)
            XCTAssertEqual(layer.rows[0].count, 10)
        }
    }
    func testDoubleTapBoundaryLocksUntilTap() {
        for interval in [299, 300, 301] {
            var shift = ManualShiftState()
            shift.tap(at: .zero)
            shift.tap(at: .milliseconds(interval))
            if interval <= 300 {
                XCTAssertEqual(shift.mode, .locked)
                XCTAssertEqual(shift.type("a"), "A")
                XCTAssertEqual(shift.type("b"), "B")
                shift.tap(at: .seconds(1))
            }
            XCTAssertEqual(shift.mode, .off)
        }
    }
    func testTypingBreaksDoubleTapAndSpacePreservesShift() {
        var state = ManualKeyboardState()
        state.shift.tap(at: .zero)
        XCTAssertEqual(state.type(" "), " ")
        XCTAssertEqual(state.type("a"), "A")
        state.shift.tap(at: .milliseconds(100))
        XCTAssertEqual(state.shift.mode, .once)
        state.select(.numbers)
        XCTAssertEqual(state.type("1"), "1")
        state.select(.letters)
        XCTAssertEqual(state.type("b"), "B")
        XCTAssertEqual(state.type("c"), "c")
    }
    func testSentenceAndDoubleSpaceContext() {
        for text in ["", "Hello. ", "What? ", "Yes! ", "hi\n"] {
            XCTAssertTrue(ManualKeyboardState.sentenceStart(before: text))
        }
        for text: String? in [nil, "Hello", "Hello "] {
            XCTAssertFalse(ManualKeyboardState.sentenceStart(before: text))
        }
        for text in ["a ", "9 "] { XCTAssertTrue(ManualKeyboardState.replacesSpace(before: text)) }
        for text: String? in [nil, "", " ", "a  ", ". ", "\n "] {
            XCTAssertFalse(ManualKeyboardState.replacesSpace(before: text))
        }
    }
}
