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
        let migrated = try session.snapshot()
        XCTAssertEqual(migrated.version, 3)
        XCTAssertEqual(migrated.request?.id, id)
        XCTAssertEqual(migrated.text, "Hello")
        try session.setStopMessage("No speech detected", requestID: id)
        XCTAssertEqual(try session.snapshot().stopMessage, "No speech detected")
    }
    func testVersionTwoFileMigratesWithRecoveryDefaults() throws {
        let storage = DictationSessionTests.Storage()
        let session = DictationSession(storage: storage)
        let id = try ready(session)
        try session.setStopMessage("Reached the 3-minute limit.", requestID: id)
        let original = try session.snapshot()
        // A real v2 record has neither of the v3 recovery fields.
        try storage.transaction { data in
            var object = try JSONSerialization.jsonObject(with: data!) as! [String: Any]
            object["version"] = 2
            object.removeValue(forKey: "heartbeatAt")
            object.removeValue(forKey: "recoveryAvailable")
            data = try JSONSerialization.data(withJSONObject: object)
        }
        let reopened = DictationSession(storage: storage)
        let migrated = try reopened.snapshot()
        XCTAssertEqual(migrated.version, 3)
        XCTAssertEqual(migrated.request, original.request)
        XCTAssertEqual(migrated.state, .ready)
        XCTAssertEqual(migrated.text, "Hello")
        XCTAssertEqual(migrated.expiresAt, original.expiresAt)
        XCTAssertEqual(migrated.stopMessage, "Reached the 3-minute limit.")
        XCTAssertNil(migrated.heartbeatAt)
        XCTAssertNil(migrated.recoveryAvailable)
        // The migrated file must remain readable by a fresh session.
        XCTAssertEqual(try DictationSession(storage: storage).snapshot(), migrated)
    }

}
