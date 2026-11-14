import Foundation
import XCTest
@testable import HandyKit

@available(macOS 14.0, *)
@MainActor
final class TranscriptionFlowTests: XCTestCase {
    final class Background: TranscriptionBackgroundTask {
        var granted = true
        var begins = 0
        var ends = 0
        var expiration: (@MainActor @Sendable () -> Void)?
        func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> Bool {
            begins += 1
            self.expiration = expiration
            return granted
        }
        func end() { ends += 1 }
    }
    actor ASR: BatchASR {
        let fails: Bool
        let suspended: Bool
        var started = false
        var startWaiter: CheckedContinuation<Void, Never>?
        var completion: CheckedContinuation<Void, Never>?
        init(suspended: Bool = false, fails: Bool = false) { self.suspended = suspended; self.fails = fails }
        func waitUntilStarted() async {
            if started { return }
            await withCheckedContinuation { startWaiter = $0 }
        }
        var cancelled = false
        var cleaned = false
        func transcribe(_ audio: ASRAudio) async throws -> ASRTranscription {
            if fails { throw ASRError.modelsUnavailable }
            started = true
            startWaiter?.resume()
            startWaiter = nil
            if suspended { await withCheckedContinuation { completion = $0 } }
            // Return a late success even after cancel to exercise the publication guard.
            return ASRTranscription(text: "Hello", loadSeconds: 0, runSeconds: 0)
        }
        func cancel() {
            cancelled = true
            completion?.resume()
            completion = nil
        }
        func cleanup() { cleaned = true }
    }
    func testBackgroundBeginsBeforeCaptureFinishesAndEndsOnSuccess() async throws {
        let session = DictationSession(storage: DictationSessionTests.Storage())
        let id = try session.request().id
        _ = try session.startRecording(requestID: id)
        let background = Background()
        let asr = ASR()
        let flow = TranscriptionFlow(asr: asr, background: background, session: session, id: id)
        flow.prepare()
        XCTAssertEqual(background.begins, 1)
        XCTAssertEqual(try session.snapshot().state, .recording)
        _ = try session.finishCapture(requestID: id)
        await flow.transcribe(samples: [0.1])
        XCTAssertEqual(try session.snapshot().text, "Hello")
        XCTAssertEqual(background.ends, 1)
        XCTAssertTrue(flow.retainedAudio.isEmpty)
        let cleaned = await asr.cleaned
        XCTAssertTrue(cleaned)
    }

    func testExpiryCancelsASRRetainsAudioAndRejectsLateResult() async throws {
        let session = DictationSession(storage: DictationSessionTests.Storage())
        let id = try session.request().id
        _ = try session.startRecording(requestID: id)
        let background = Background()
        let asr = ASR(suspended: true)
        let flow = TranscriptionFlow(asr: asr, background: background, session: session, id: id)
        flow.prepare()
        _ = try session.finishCapture(requestID: id)
        let task = Task { await flow.transcribe(samples: [0.1, -0.2]) }
        await asr.waitUntilStarted()
        background.expiration?()
        XCTAssertEqual(background.ends, 1)
        XCTAssertEqual(try session.snapshot().state, .failed)
        XCTAssertTrue(try XCTUnwrap(session.snapshot().stopMessage).contains("retry"))
        await task.value
        XCTAssertEqual(flow.retainedAudio, [0.1, -0.2])
        XCTAssertNil(try session.snapshot().text)
        XCTAssertNil(flow.text)
        let cancelled = await asr.cancelled
        let cleaned = await asr.cleaned
        XCTAssertTrue(cancelled)
        XCTAssertTrue(cleaned)
        XCTAssertEqual(background.ends, 1)
    }

    func testCancelEndsBackgroundAndDiscardsAudio() async throws {
        let session = DictationSession(storage: DictationSessionTests.Storage())
        let id = try session.request().id
        _ = try session.startRecording(requestID: id)
        let background = Background()
        let asr = ASR(suspended: true)
        let flow = TranscriptionFlow(asr: asr, background: background, session: session, id: id)
        flow.prepare()
        _ = try session.finishCapture(requestID: id)
        let task = Task { await flow.transcribe(samples: [0.1]) }
        await asr.waitUntilStarted()
        flow.cancel()
        await task.value
        XCTAssertEqual(background.ends, 1)
        XCTAssertEqual(try session.snapshot().state, .idle)
        XCTAssertTrue(flow.retainedAudio.isEmpty)
        XCTAssertNil(flow.text)
        let cancelled = await asr.cancelled
        XCTAssertTrue(cancelled)
    }

    func testDeniedBackgroundTimeKeepsCapturedAudioForRetry() async throws {
        let session = DictationSession(storage: DictationSessionTests.Storage())
        let id = try session.request().id
        _ = try session.startRecording(requestID: id)
        let background = Background()
        background.granted = false
        let asr = ASR()
        let flow = TranscriptionFlow(asr: asr, background: background, session: session, id: id)
        flow.prepare()
        await flow.transcribe(samples: [0.1])
        XCTAssertEqual(try session.snapshot().state, .failed)
        XCTAssertEqual(flow.retainedAudio, [0.1])
        XCTAssertEqual(background.ends, 1)
        XCTAssertNil(flow.text)
    }

    func testASRFailureEndsBackgroundAndKeepsAudio() async throws {
        let session = DictationSession(storage: DictationSessionTests.Storage())
        let id = try session.request().id
        _ = try session.startRecording(requestID: id)
        let background = Background()
        let asr = ASR(fails: true)
        let flow = TranscriptionFlow(asr: asr, background: background, session: session, id: id)
        flow.prepare()
        _ = try session.finishCapture(requestID: id)
        await flow.transcribe(samples: [0.1])
        XCTAssertEqual(try session.snapshot().state, .failed)
        XCTAssertEqual(flow.retainedAudio, [0.1])
        XCTAssertEqual(background.ends, 1)
        let cleaned = await asr.cleaned
        XCTAssertTrue(cleaned)
    }

    func testParentCancellationCancelsASRWithoutFailedResult() async throws {
        let session = DictationSession(storage: DictationSessionTests.Storage())
        let id = try session.request().id
        _ = try session.startRecording(requestID: id)
        let background = Background()
        let asr = ASR(suspended: true)
        let flow = TranscriptionFlow(asr: asr, background: background, session: session, id: id)
        flow.prepare()
        _ = try session.finishCapture(requestID: id)
        let task = Task { await flow.transcribe(samples: [0.1]) }
        await asr.waitUntilStarted()
        task.cancel()
        await task.value
        XCTAssertEqual(try session.snapshot().state, .idle)
        XCTAssertEqual(background.ends, 1)
        XCTAssertTrue(flow.retainedAudio.isEmpty)
        let cleaned = await asr.cleaned
        XCTAssertTrue(cleaned)
    }
}
