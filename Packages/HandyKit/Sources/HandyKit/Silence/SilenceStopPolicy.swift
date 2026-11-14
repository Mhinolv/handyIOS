import Foundation

public enum SilenceDelay: Int, CaseIterable, Sendable {
    case off = 0, one, two, three, four, five
    public static let storageKey = "silenceDelaySeconds"
    public static let defaultValue = SilenceDelay.two
    public static func stored(in defaults: UserDefaults = .standard) -> Self {
        guard defaults.object(forKey: storageKey) != nil else { return .two }
        return Self(rawValue: defaults.integer(forKey: storageKey)) ?? .two
    }
    public var title: String {
        switch self {
        case .off: return "Off"
        case .one: return "1 second"
        default: return "\(rawValue) seconds"
        }
    }
}

/// Frame time is measured from microphone readiness, not detector completion.
public struct SpeechProbability: Sendable {
    public let probability: Float
    public let elapsed: TimeInterval
    public init(probability: Float, elapsed: TimeInterval) {
        self.probability = probability
        self.elapsed = elapsed
    }
}

public protocol VoiceActivityDetecting {
    /// Accept mono 16 kHz PCM. Return frame probabilities without segment padding.
    func process(_ samples: [Float]) throws -> [SpeechProbability]
    func reset() throws
}

public enum CaptureStopReason: Equatable, Sendable {
    case silence, userStop, noSpeech, interruption, durationCap
}

/// Confine calls to the capture owner. No RMS fallback or SDK segment delay.
public final class SilenceStopPolicy: CaptureStopPolicy {
    public let delay: SilenceDelay
    public private(set) var hasSpeech = false
    public private(set) var failure: String?
    public private(set) var stopReason: CaptureStopReason?
    private let now: () -> TimeInterval
    private var startedAt: TimeInterval?
    private var lastSpeech: TimeInterval?
    public init(delay: SilenceDelay = .two,
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.delay = delay
        self.now = now
    }
    public func microphoneReady() {
        startedAt = now()
        lastSpeech = nil
        hasSpeech = false
        stopReason = nil
    }
    public func receive(_ frame: SpeechProbability) {
        guard let start = startedAt, failure == nil, stopReason == nil,
              frame.elapsed.isFinite, frame.elapsed >= 0,
              frame.elapsed <= now() - start,
              frame.probability.isFinite, (0...1).contains(frame.probability) else { return }
        if frame.probability >= 0.5 {
            hasSpeech = true
            lastSpeech = max(lastSpeech ?? 0, frame.elapsed)
        }
    }
    public func detectorFailed(_ message: String) { failure = message }
    public func shouldStop(_ progress: CaptureProgress) -> Bool {
        guard let start = startedAt, failure == nil else { return false }
        if stopReason != nil { return true }
        let elapsed = now() - start
        if let lastSpeech {
            if delay != .off && elapsed - lastSpeech >= Double(delay.rawValue) { stopReason = .silence }
        } else if elapsed >= 10 { stopReason = .noSpeech }
        return stopReason != nil
    }
}
