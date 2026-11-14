import XCTest
@testable import HandyKit

final class SilenceStopPolicyTests: XCTestCase {
    private final class Clock { var time: Double = 0 }
    private let progress = CaptureProgress(sampleCount: 0, level: 1)

    func testFakeDetectorFeedsProbabilities() async throws {
        struct FakeDetector: VoiceActivityDetecting {
            func reset() async throws {}
            func process(_ samples: [Float]) async throws -> [SpeechProbability] {
                [.init(probability: 0.9, elapsed: 1), .init(probability: 0.1, elapsed: 2)]
            }
        }
        let clock = Clock()
        let policy = SilenceStopPolicy(now: { clock.time })
        policy.microphoneReady()
        clock.time = 2
        for frame in try await FakeDetector().process([0, 0]) { policy.receive(frame) }
        XCTAssertTrue(policy.hasSpeech)
        XCTAssertFalse(policy.shouldStop(progress))
        clock.time = 3
        XCTAssertTrue(policy.shouldStop(progress))
        XCTAssertEqual(policy.stopReason, .silence)
    }

    func testInitialTimerStartsOnlyAtMicrophoneReadiness() {
        let clock = Clock()
        let policy = SilenceStopPolicy(now: { clock.time })
        clock.time = 100
        XCTAssertFalse(policy.shouldStop(progress))
        policy.microphoneReady()
        clock.time = 109.99
        XCTAssertFalse(policy.shouldStop(progress))
        clock.time = 110
        XCTAssertTrue(policy.shouldStop(progress))
        XCTAssertEqual(policy.stopReason, .noSpeech)
    }

    func testEveryDelayAndResumedSpeech() {
        for delay in SilenceDelay.allCases where delay != .off {
            let clock = Clock()
            let policy = SilenceStopPolicy(delay: delay, now: { clock.time })
            policy.microphoneReady()
            clock.time = 1
            policy.receive(.init(probability: 0.9, elapsed: 1))
            clock.time = 1.5
            policy.receive(.init(probability: 0.1, elapsed: 1.5))
            XCTAssertFalse(policy.shouldStop(progress))
            clock.time = 1.9
            policy.receive(.init(probability: 0.8, elapsed: 1.9))
            clock.time = 1.9 + Double(delay.rawValue) - 0.01
            XCTAssertFalse(policy.shouldStop(progress))
            clock.time += 0.02
            XCTAssertTrue(policy.shouldStop(progress))
            XCTAssertEqual(policy.stopReason, .silence)
        }
    }

    func testOffKeepsInitialLimitButDoesNotStopAfterSpeech() {
        let clock = Clock()
        let policy = SilenceStopPolicy(delay: .off, now: { clock.time })
        policy.microphoneReady()
        clock.time = 10
        XCTAssertTrue(policy.shouldStop(progress))
        policy.microphoneReady()
        policy.receive(.init(probability: 1, elapsed: 0))
        clock.time = 100
        XCTAssertFalse(policy.shouldStop(progress))
    }

    func testDelayedProbabilityUsesFrameTimeWithoutExtraSegmentDelay() {
        let clock = Clock()
        let policy = SilenceStopPolicy(now: { clock.time })
        policy.microphoneReady()
        clock.time = 3
        policy.receive(.init(probability: 1, elapsed: 1))
        XCTAssertTrue(policy.shouldStop(progress))
    }

    func testFailureDisablesBothTimersAndNeverUsesLevel() {
        let clock = Clock()
        let policy = SilenceStopPolicy(now: { clock.time })
        policy.microphoneReady()
        policy.detectorFailed("VAD failed")
        clock.time = 100
        XCTAssertFalse(policy.shouldStop(progress))
        XCTAssertEqual(policy.failure, "VAD failed")
    }

    func testInvalidAndOutOfOrderFrames() {
        let clock = Clock()
        let policy = SilenceStopPolicy(now: { clock.time })
        policy.microphoneReady()
        clock.time = 3
        policy.receive(.init(probability: .nan, elapsed: 3))
        policy.receive(.init(probability: 1, elapsed: 4))
        XCTAssertFalse(policy.hasSpeech)
        policy.receive(.init(probability: 1, elapsed: 3))
        policy.receive(.init(probability: 1, elapsed: 1))
        clock.time = 4
        XCTAssertFalse(policy.shouldStop(progress))
    }

    func testStoredChoicesAndTolerantDefault() {
        let name = "SilenceTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(SilenceDelay.stored(in: defaults), .two)
        for choice in SilenceDelay.allCases {
            defaults.set(choice.rawValue, forKey: SilenceDelay.storageKey)
            XCTAssertEqual(SilenceDelay.stored(in: defaults), choice)
        }
        defaults.set(99, forKey: SilenceDelay.storageKey)
        XCTAssertEqual(SilenceDelay.stored(in: defaults), .two)
    }
}
