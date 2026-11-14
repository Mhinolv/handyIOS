import XCTest
@testable import HandyKit

private actor FakeASR: BatchASR {
    private(set) var received: ASRAudio?
    private(set) var released = false
    func transcribe(_ audio: ASRAudio) async throws -> ASRTranscription {
        try Task.checkCancellation()
        received = audio
        return ASRTranscription(text: "Local speech", loadSeconds: 1, runSeconds: 2)
    }
    func cancel() { received = nil; released = true }
    func cleanup() { received = nil; released = true }
}

final class BatchASRTests: XCTestCase {
    func testRejectsUnsupportedFormats() {
        XCTAssertThrowsError(try ASRAudio(samples: [0], sampleRate: 48_000))
        XCTAssertThrowsError(try ASRAudio(samples: [0], channels: 2))
    }
    func testRejectsInvalidSamples() {
        for samples: [Float] in [[], [.nan], [.infinity], [-.infinity], [1.01], [-1.01]] {
            XCTAssertThrowsError(try ASRAudio(samples: samples))
        }
    }
    func testAcceptsSilenceAndNormalizedLimits() throws {
        XCTAssertEqual(try ASRAudio(samples: [-1, 0, 1]).samples, [-1, 0, 1])
        XCTAssertEqual(try ASRAudio(samples: [0]).samples, [0])
    }
    func testFakeThroughProtocol() async throws {
        let fake = FakeASR()
        let engine: any BatchASR = fake
        let audio = try ASRAudio(samples: [0, 0.5])
        let result = try await engine.transcribe(audio)
        XCTAssertEqual(result.text, "Local speech")
        let received = await fake.received
        XCTAssertEqual(received, audio)
        await engine.cleanup()
        let released = await fake.released
        XCTAssertTrue(released)
        let cleared = await fake.received
        XCTAssertNil(cleared)
    }
    func testFakeCancelReleasesAudio() async throws {
        let fake = FakeASR()
        _ = try await fake.transcribe(ASRAudio(samples: [0]))
        await fake.cancel()
        let received = await fake.received
        XCTAssertNil(received)
    }
    func testCancelledCallerDoesNotProduceText() async throws {
        let fake = FakeASR()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fake.transcribe(ASRAudio(samples: [0]))
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let received = await fake.received
            XCTAssertNil(received)
        }
    }

}
