import Foundation
import XCTest
@testable import HandyKit

final class ResultDeliveryTests: XCTestCase {
    private func ready(_ session: DictationSession) throws -> UUID {
        let id = try session.request().id
        XCTAssertTrue(try session.startRecording(requestID: id))
        XCTAssertTrue(try session.finishCapture(requestID: id))
        XCTAssertTrue(try session.publish(text: "Hello", requestID: id))
        return id
    }
    func testLiveDeliverySpacesAndClearsResult() throws {
        for before in ["word", "word.", "word ", "", "\n"] {
            let session = DictationSession(storage: DictationSessionTests.Storage())
            let id = try ready(session)
            let focus = DeliveryFocus(document: UUID(), before: before, after: "")
            let consumer = ResultDelivery()
            consumer.begin(requestID: id, focus: focus)
            var output = ""
            XCTAssertTrue(try consumer.insert(session: session, focus: focus) { output += $0 })
            XCTAssertEqual(output, (["word", "word."].contains(before) ? " " : "") + "Hello")
            XCTAssertFalse(try consumer.insert(session: session, focus: focus) { output += $0 })
            XCTAssertNil(try session.snapshot().text)
        }
    }
    func testEmptyFieldAutomaticallyInsertsOnce() throws {
        let session = DictationSession(storage: DictationSessionTests.Storage())
        let id = try ready(session)
        let document = UUID()
        let consumer = ResultDelivery()
        consumer.begin(requestID: id, focus: DeliveryFocus(document: document, before: nil, after: nil))
        let focus = DeliveryFocus(document: document, before: "", after: nil)
        var output: [String] = []
        XCTAssertTrue(try consumer.insert(session: session, focus: focus) { output.append($0) })
        XCTAssertFalse(try consumer.insert(session: session, focus: focus) { output.append($0) })
        XCTAssertEqual(output, ["Hello"])
    }

    func testChangedFocusAndReloadRequireTap() throws {
        let session = DictationSession(storage: DictationSessionTests.Storage())
        let id = try ready(session)
        let original = DeliveryFocus(document: UUID(), before: "", after: "")
        let changed = DeliveryFocus(document: UUID(), before: "", after: "")
        let consumer = ResultDelivery()
        consumer.begin(requestID: id, focus: original)
        XCTAssertFalse(try consumer.insert(session: session, focus: changed) { _ in XCTFail() })
        let recreated = ResultDelivery()
        XCTAssertFalse(try recreated.insert(session: session, focus: original) { _ in XCTFail() })
        XCTAssertTrue(try recreated.insert(session: session, focus: changed, explicit: true) { XCTAssertEqual($0, "Hello") })
    }
    func testFailedAcknowledgementAndCrashClaim() throws {
        let storage = DictationSessionTests.Storage()
        let session = DictationSession(storage: storage)
        let id = try ready(session)
        let focus = DeliveryFocus(document: UUID(), before: "", after: "")
        let consumer = ResultDelivery()
        consumer.begin(requestID: id, focus: focus)
        var count = 0
        XCTAssertThrowsError(try consumer.insert(session: session, focus: focus) { _ in
            count += 1
            storage.rejectWrites = true
        })
        storage.rejectWrites = false
        let recreated = ResultDelivery()
        recreated.begin(requestID: id, focus: focus)
        XCTAssertFalse(try recreated.insert(session: session, focus: focus) { _ in XCTFail() })
        XCTAssertTrue(try consumer.insert(session: session, focus: focus) { _ in XCTFail() })
        XCTAssertEqual(count, 1)
    }
    func testLegacyDecodePreservesRequestAndStopMessage() throws {
        let storage = DictationSessionTests.Storage()
        let session = DictationSession(storage: storage)
        let id = try ready(session)
        try storage.transaction { data in
            var object = try JSONSerialization.jsonObject(with: data!) as! [String: Any]
            object["version"] = 1
            object.removeValue(forKey: "deliveryClaim")
            object.removeValue(forKey: "stopMessage")
            data = try JSONSerialization.data(withJSONObject: object)
        }
        XCTAssertEqual(try session.snapshot().version, 2)
        try session.setStopMessage("No speech detected", requestID: id)
        XCTAssertEqual(try session.snapshot().stopMessage, "No speech detected")
    }
}
