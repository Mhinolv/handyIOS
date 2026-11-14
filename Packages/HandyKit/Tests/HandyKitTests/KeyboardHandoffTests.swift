import Foundation
import XCTest
@testable import HandyKit

final class KeyboardHandoffTests: XCTestCase {
    private typealias Storage = DictationSessionTests.Storage

    func testURLIdentityAndInvalidURLs() {
        let id = UUID()
        XCTAssertEqual(KeyboardHandoff.requestID(from: KeyboardHandoff.url(requestID: id)), id)
        for url in ["https://dictate/\(id)", "handyios://other/\(id)", "handyios://dictate/invalid",
                    "handyios://dictate/\(id)/extra"] {
            XCTAssertNil(KeyboardHandoff.requestID(from: URL(string: url)!))
        }
    }

    func testFakeRoundTripAndDuplicateDelivery() throws {
        let storage = Storage()
        let keyboard = DictationSession(storage: storage)
        let app = DictationSession(storage: storage)
        let request = try keyboard.request()
        XCTAssertFalse(try KeyboardHandoff.publishFakeResult(session: app, requestID: UUID()))
        XCTAssertTrue(try KeyboardHandoff.publishFakeResult(session: app, requestID: request.id))
        XCTAssertFalse(try KeyboardHandoff.publishFakeResult(session: app, requestID: request.id))
        let consumer = KeyboardResultConsumer()
        var inserted: [String] = []
        XCTAssertFalse(try consumer.consume(session: keyboard, requestID: UUID()) { inserted.append($0) })
        XCTAssertTrue(try consumer.consume(session: keyboard, requestID: request.id) { inserted.append($0) })
        XCTAssertFalse(try consumer.consume(session: keyboard, requestID: request.id) { inserted.append($0) })
        XCTAssertEqual(inserted, ["handyIOS test text."])
        XCTAssertEqual(try app.snapshot().state, .idle)
    }

    func testAcknowledgementRetryDoesNotInsertTwice() throws {
        let storage = Storage()
        let session = DictationSession(storage: storage)
        let request = try session.request()
        XCTAssertTrue(try KeyboardHandoff.publishFakeResult(session: session, requestID: request.id))
        let consumer = KeyboardResultConsumer()
        var inserted: [String] = []
        // Reject acknowledgement after insertion, rather than the initial snapshot read.
        XCTAssertThrowsError(try consumer.consume(session: session, requestID: request.id) {
            inserted.append($0)
            storage.rejectWrites = true
        })
        storage.rejectWrites = false
        XCTAssertTrue(try consumer.consume(session: session, requestID: request.id) { inserted.append($0) })
        XCTAssertEqual(inserted.count, 1)
    }

    func testStoppedAndExpiredRequestsDoNotPublish() throws {
        let clock = DictationSessionTests.Clock()
        let session = DictationSession(storage: Storage(), clock: clock)
        let stopped = try session.request()
        XCTAssertTrue(try session.requestStop(requestID: stopped.id))
        _ = try KeyboardHandoff.publishFakeResult(session: session, requestID: stopped.id)
        XCTAssertEqual(try session.snapshot().state, .idle)
        let expired = try session.request()
        clock.now.addTimeInterval(181)
        XCTAssertFalse(try KeyboardHandoff.publishFakeResult(session: session, requestID: expired.id))
        XCTAssertNil(try session.snapshot().text)
    }
}
