import Foundation
import XCTest
@testable import HandyKit

final class DictationSessionTests: XCTestCase {
    final class Clock: SessionClock {
        var now = Date(timeIntervalSince1970: 1000)
    }

    final class Storage: SessionStorage {
        var data: Data?
        var rejectWrites = false
        func transaction<T>(_ body: (inout Data?) throws -> T) throws -> T {
            var copy = data
            let result = try body(&copy)
            if rejectWrites { throw CocoaError(.fileWriteNoPermission) }
            data = copy
            return result
        }
    }

    func testLifecycleAcrossClientsAndAcknowledgement() throws {
        let storage = Storage()
        let clock = Clock()
        let keyboard = DictationSession(storage: storage, clock: clock)
        let app = DictationSession(storage: storage, clock: clock)
        XCTAssertEqual(try keyboard.snapshot().state, .idle)
        let request = try keyboard.request()
        XCTAssertEqual(try app.snapshot().request, request)
        XCTAssertEqual(try app.snapshot().state, .requested)
        XCTAssertFalse(try app.publish(text: "early", requestID: request.id))
        XCTAssertTrue(try app.startRecording(requestID: request.id))
        XCTAssertFalse(try app.startRecording(requestID: request.id))
        XCTAssertTrue(try app.startTranscription(requestID: request.id))
        XCTAssertTrue(try app.publish(text: "Hello", requestID: request.id))
        XCTAssertEqual(try keyboard.snapshot().text, "Hello")
        XCTAssertFalse(try app.publish(text: "Duplicate", requestID: request.id))
        XCTAssertFalse(try keyboard.acknowledge(requestID: UUID()))
        XCTAssertEqual(try keyboard.snapshot().text, "Hello")
        XCTAssertThrowsError(try keyboard.request())
        XCTAssertTrue(try keyboard.acknowledge(requestID: request.id))
        XCTAssertNil(try app.snapshot().text)
        XCTAssertFalse(try keyboard.acknowledge(requestID: request.id))
        let next = try keyboard.request()
        XCTAssertNotEqual(next.id, request.id)
        XCTAssertFalse(try app.publish(text: "Old", requestID: request.id))
    }

    func testOverlapAndInvalidTransitionsPreserveSession() throws {
        let session = DictationSession(storage: Storage(), clock: Clock())
        let request = try session.request()
        let before = try session.snapshot()
        XCTAssertThrowsError(try session.request()) { XCTAssertEqual($0 as? DictationProtocolError, .busy) }
        XCTAssertFalse(try session.startTranscription(requestID: request.id))
        XCTAssertFalse(try session.startRecording(requestID: UUID()))
        XCTAssertFalse(try session.cancel(requestID: UUID()))
        XCTAssertEqual(try session.snapshot(), before)
        XCTAssertTrue(try session.cancel(requestID: request.id))
        XCTAssertEqual(try session.snapshot().state, .idle)
    }

    func testCaptureExpiryAfterThreeMinutesRejectsLateResult() throws {
        let clock = Clock()
        let session = DictationSession(storage: Storage(), clock: clock)
        let request = try session.request()
        XCTAssertTrue(try session.startRecording(requestID: request.id))
        clock.now.addTimeInterval(179.999)
        XCTAssertEqual(try session.snapshot().state, .recording)
        clock.now.addTimeInterval(0.002)
        XCTAssertFalse(try session.requestStop(requestID: request.id))
        XCTAssertFalse(try session.publish(text: "Late", requestID: request.id))
        XCTAssertEqual(try session.snapshot().state, .idle)
        XCTAssertNil(try session.snapshot().request)
        XCTAssertNotEqual(try session.request().id, request.id)
    }

    func testFullThreeMinuteCaptureHasSeparateTranscriptionWindow() throws {
        let clock = Clock()
        let session = DictationSession(storage: Storage(), clock: clock)
        let request = try session.request()
        XCTAssertTrue(try session.startRecording(requestID: request.id))
        clock.now.addTimeInterval(180)
        XCTAssertEqual(try session.snapshot().state, .recording)
        XCTAssertTrue(try session.startTranscription(requestID: request.id))
        XCTAssertEqual(try session.snapshot().expiresAt, clock.now.addingTimeInterval(120))
        clock.now.addTimeInterval(119.999)
        XCTAssertEqual(try session.snapshot().state, .transcribing)
        XCTAssertTrue(try session.publish(text: "Full capture", requestID: request.id))
        XCTAssertEqual(try session.snapshot().text, "Full capture")
    }

    func testTranscriptionExpiresAtItsOwnDeadline() throws {
        let clock = Clock()
        let session = DictationSession(storage: Storage(), clock: clock)
        let request = try session.request()
        XCTAssertTrue(try session.startRecording(requestID: request.id))
        clock.now.addTimeInterval(180)
        XCTAssertTrue(try session.startTranscription(requestID: request.id))
        clock.now.addTimeInterval(120)
        XCTAssertFalse(try session.publish(text: "Late", requestID: request.id))
        XCTAssertEqual(try session.snapshot().state, .idle)
    }

    func testCaptureDeadlineStartsWhenRecordingStarts() throws {
        let clock = Clock()
        let session = DictationSession(storage: Storage(), clock: clock)
        let request = try session.request()
        clock.now.addTimeInterval(100)
        XCTAssertTrue(try session.startRecording(requestID: request.id))
        clock.now.addTimeInterval(180)
        XCTAssertEqual(try session.snapshot().state, .recording)
        XCTAssertTrue(try session.startTranscription(requestID: request.id))
        clock.now.addTimeInterval(119)
        XCTAssertTrue(try session.publish(text: "Delayed start", requestID: request.id))
    }

    func testUnclaimedResultExpiresFifteenMinutesAfterPublication() throws {
        let storage = Storage()
        let clock = Clock()
        let session = DictationSession(storage: storage, clock: clock)
        let request = try session.request()
        XCTAssertTrue(try session.startRecording(requestID: request.id))
        XCTAssertTrue(try session.startTranscription(requestID: request.id))
        clock.now.addTimeInterval(100)
        XCTAssertTrue(try session.publish(text: "Private text", requestID: request.id))
        clock.now.addTimeInterval(899.999)
        XCTAssertEqual(try session.snapshot().text, "Private text")
        clock.now.addTimeInterval(0.001)
        XCTAssertFalse(try session.acknowledge(requestID: request.id))
        XCTAssertEqual(try session.snapshot().state, .idle)
        XCTAssertNil(try session.snapshot().text)
        XCTAssertFalse(String(decoding: storage.data!, as: UTF8.self).contains("Private text"))
    }

    func testStopRequestMatchesLiveRequestOnly() throws {
        let session = DictationSession(storage: Storage(), clock: Clock())
        XCTAssertFalse(try session.requestStop(requestID: UUID()))
        let first = try session.request()
        XCTAssertTrue(try session.requestStop(requestID: first.id))
        XCTAssertTrue(try session.snapshot().stopRequested)
        XCTAssertTrue(try session.cancel(requestID: first.id))
        let next = try session.request()
        XCTAssertFalse(try session.snapshot().stopRequested)
        XCTAssertTrue(try session.startRecording(requestID: next.id))
        XCTAssertFalse(try session.requestStop(requestID: first.id))
        XCTAssertFalse(try session.requestStop(requestID: UUID()))
        XCTAssertFalse(try session.snapshot().stopRequested)
        XCTAssertTrue(try session.requestStop(requestID: next.id))
        XCTAssertTrue(try session.requestStop(requestID: next.id))
        XCTAssertTrue(try session.startTranscription(requestID: next.id))
        XCTAssertFalse(try session.requestStop(requestID: next.id))
    }

    func testFailureExpiresAndWriteFailurePreservesData() throws {
        let storage = Storage()
        let clock = Clock()
        let session = DictationSession(storage: storage, clock: clock)
        let request = try session.request()
        let original = storage.data
        storage.rejectWrites = true
        XCTAssertThrowsError(try session.startRecording(requestID: request.id))
        XCTAssertEqual(storage.data, original)
        storage.rejectWrites = false
        XCTAssertTrue(try session.fail(requestID: request.id))
        XCTAssertEqual(try session.snapshot().state, .failed)
        XCTAssertFalse(try session.publish(text: "No", requestID: request.id))
        clock.now.addTimeInterval(180)
        XCTAssertEqual(try session.snapshot().state, .idle)
    }

    func testCorruptOrFutureDataIsNotOverwritten() throws {
        let storage = Storage()
        let session = DictationSession(storage: storage)
        for json in ["invalid", "{\"version\":2,\"state\":\"idle\",\"stopRequested\":false}"] {
            storage.data = Data(json.utf8)
            XCTAssertThrowsError(try session.request())
            XCTAssertEqual(storage.data, Data(json.utf8))
        }
    }

    func testFileStorageSharesStateAndRollsBackFailedTransaction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = AppGroupSessionStorage(directory: directory)
        let second = AppGroupSessionStorage(directory: directory)
        let keyboard = DictationSession(storage: first)
        let app = DictationSession(storage: second)
        let request = try keyboard.request()
        XCTAssertEqual(try app.snapshot().request, request)
        XCTAssertTrue(try app.requestStop(requestID: request.id))
        XCTAssertTrue(try keyboard.snapshot().stopRequested)
        XCTAssertThrowsError(try first.transaction { data in
            data = nil
            throw CocoaError(.userCancelled)
        })
        XCTAssertEqual(try app.snapshot().request, request)
    }

    func testConcurrentFileClientsAcceptExactlyOneRequest() throws {
        final class Outcomes: @unchecked Sendable {
            let lock = NSLock()
            var accepted: [UUID] = []
            var failures = 0
            func record(_ id: UUID?, unexpected: Bool = false) {
                lock.lock()
                defer { lock.unlock() }
                if let id { accepted.append(id) }
                if unexpected { failures += 1 }
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outcomes = Outcomes()
        DispatchQueue.concurrentPerform(iterations: 24) { _ in
            let client = DictationSession(storage: AppGroupSessionStorage(directory: directory))
            do { outcomes.record(try client.request().id) }
            catch DictationProtocolError.busy { }
            catch { outcomes.record(nil, unexpected: true) }
        }
        XCTAssertEqual(outcomes.failures, 0)
        XCTAssertEqual(outcomes.accepted.count, 1)
        let reader = DictationSession(storage: AppGroupSessionStorage(directory: directory))
        XCTAssertEqual(try reader.snapshot().request?.id, outcomes.accepted.first)
    }

}
