import XCTest
@testable import HandyKit

@MainActor
private final class FakeMicrophone: MicrophoneEngine {
    var allowed = true
    var throwsOnStart = false
    var active = false
    var stops = 0
    let buffer = CaptureBuffer()
    func requestPermission() async -> Bool { allowed }
    func start() throws {
        if throwsOnStart { throw NSError(domain: "test", code: 1) }
        active = true
    }
    var progress: CaptureProgress { buffer.progress }
    func stop() -> [Float] { active = false; stops += 1; return buffer.take() }
}

final class MicrophoneSessionTests: XCTestCase {
    @MainActor func testSilencePolicyReleasesMicrophoneAndDistinguishesReasons() async {
        var time: Double = 0
        let policy = SilenceStopPolicy(now: { time })
        let engine = FakeMicrophone()
        let session = MicrophoneSession(engine: engine, policy: policy)
        await session.start()
        time = 10
        session.tick()
        XCTAssertEqual(session.stopReason, .noSpeech)
        XCTAssertFalse(engine.active)
        XCTAssertEqual(engine.stops, 1)
        XCTAssertTrue(session.audio.isEmpty)
    }
    @MainActor func testDeniedDoesNotStart() async {
        let engine = FakeMicrophone()
        engine.allowed = false
        let session = MicrophoneSession(engine: engine)
        await session.start()
        XCTAssertEqual(session.state, .denied)
        XCTAssertFalse(engine.active)
    }
    @MainActor func testStopKeepsAudioAndReleasesEngine() async {
        let engine = FakeMicrophone()
        let session = MicrophoneSession(engine: engine)
        await session.start()
        engine.buffer.append([0.1, -0.2])
        session.stop()
        session.stop()
        XCTAssertEqual(session.audio, [0.1, -0.2])
        XCTAssertEqual(session.stopReason, .userStop)
        XCTAssertFalse(engine.active)
        XCTAssertEqual(engine.stops, 1)
    }
    @MainActor func testCancelDiscardsAudio() async {
        let engine = FakeMicrophone()
        let session = MicrophoneSession(engine: engine)
        await session.start()
        engine.buffer.append([1])
        session.cancel()
        XCTAssertTrue(session.audio.isEmpty)
        XCTAssertEqual(engine.progress.sampleCount, 0)
        XCTAssertFalse(engine.active)
    }
    @MainActor func testCapTruncatesAndKeepsAudio() async {
        let engine = FakeMicrophone()
        let session = MicrophoneSession(engine: engine)
        await session.start()
        engine.buffer.append(Array(repeating: 0.5, count: CaptureBuffer.maximumSamples + 10))
        XCTAssertEqual(engine.progress.elapsed, 180)
        session.tick()
        XCTAssertTrue(session.reachedCap)
        XCTAssertEqual(session.stopReason, .durationCap)
        XCTAssertEqual(session.audio.count, CaptureBuffer.maximumSamples)
        XCTAssertFalse(engine.active)
    }
    @MainActor func testStartFailureReleasesEngine() async {
        let engine = FakeMicrophone()
        engine.throwsOnStart = true
        let session = MicrophoneSession(engine: engine)
        await session.start()
        XCTAssertEqual(session.state, .failed)
        XCTAssertEqual(engine.stops, 1)
    }
    @MainActor func testPolicyHookStopsWithoutVAD() async {
        struct Policy: CaptureStopPolicy {
            func shouldStop(_ progress: CaptureProgress) -> Bool { progress.sampleCount > 0 }
        }
        let engine = FakeMicrophone()
        let session = MicrophoneSession(engine: engine, policy: Policy())
        await session.start()
        engine.buffer.append([0])
        session.tick()
        XCTAssertEqual(session.state, .stopped)
        XCTAssertFalse(session.reachedCap)
    }
}
