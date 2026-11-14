import XCTest
@testable import HandyKit

final class LastResultTests: XCTestCase {
    func testExpiryStartsAtPublicationAndDeletesPersistedTextAtBoundary() throws {
        let clock = DictationSessionTests.Clock()
        let storage = DictationSessionTests.Storage()
        let session = DictationSession(storage: storage, clock: clock)
        XCTAssertNil(try session.lastResult())
        let id = try session.request().id
        _ = try session.startRecording(requestID: id)
        clock.now.addTimeInterval(60)
        _ = try session.finishCapture(requestID: id)
        XCTAssertNil(try session.lastResult())
        _ = try session.publish(text: "Private text", requestID: id)
        XCTAssertEqual(DictationSession.unclaimedResultLifetime, 15 * 60)
        clock.now.addTimeInterval(899)
        XCTAssertEqual(try session.lastResult()?.text, "Private text")
        clock.now.addTimeInterval(1)
        XCTAssertNil(try session.lastResult())
        XCTAssertNil(try JSONDecoder().decode(DictationSnapshot.self, from: XCTUnwrap(storage.data)).text)
    }

    func testReadDoesNotAcknowledgeAndDiscardCannotDeleteNewerResult() throws {
        let clock = DictationSessionTests.Clock()
        let storage = DictationSessionTests.Storage()
        let session = DictationSession(storage: storage, clock: clock)
        func publish(_ text: String) throws -> UUID {
            let id = try session.request().id
            _ = try session.startRecording(requestID: id)
            _ = try session.finishCapture(requestID: id)
            _ = try session.publish(text: text, requestID: id)
            return id
        }
        let first = try publish("First")
        XCTAssertEqual(try session.lastResult()?.text, "First")
        XCTAssertEqual(try session.lastResult()?.id, first)
        XCTAssertTrue(try session.discardResult(id: first))
        XCTAssertNil(try session.lastResult())
        XCTAssertNil(try JSONDecoder().decode(DictationSnapshot.self, from: XCTUnwrap(storage.data)).text)
        let second = try publish("Latest")
        XCTAssertFalse(try session.discardResult(id: first))
        XCTAssertEqual(try session.lastResult()?.id, second)
        XCTAssertTrue(try session.acknowledge(requestID: second))
        XCTAssertNil(try session.lastResult())
    }
}
