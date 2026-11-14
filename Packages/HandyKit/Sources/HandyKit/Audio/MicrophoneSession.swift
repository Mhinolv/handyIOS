import Foundation

@MainActor
public protocol MicrophoneEngine {
    func requestPermission() async -> Bool
    func start() throws
    var progress: CaptureProgress { get }
    func stop() -> [Float]
}

public struct CaptureProgress: Sendable {
    public let sampleCount: Int
    public let level: Float
    public init(sampleCount: Int, level: Float) {
        self.sampleCount = sampleCount
        self.level = level
    }
    public var elapsed: TimeInterval { Double(sampleCount) / 16_000 }
}

public protocol CaptureStopPolicy {
    func microphoneReady()
    var stopReason: CaptureStopReason? { get }
    func shouldStop(_ progress: CaptureProgress) -> Bool
}

public extension CaptureStopPolicy {
    func microphoneReady() {}
    var stopReason: CaptureStopReason? { nil }
}

public struct ManualCaptureStopPolicy: CaptureStopPolicy {
    public init() {}
    public func shouldStop(_ progress: CaptureProgress) -> Bool { false }
}

/// The audio callback owns this bounded, memory-only buffer through a lock.
public final class CaptureBuffer: @unchecked Sendable {
    public static let maximumSamples = 180 * 16_000
    private let lock = NSLock()
    private var samples: [Float] = []
    private var level: Float = 0
    private var readOffset = 0
    public init() {}
    public func append(_ input: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        let accepted = input.prefix(Self.maximumSamples - samples.count)
        samples.append(contentsOf: accepted)
        level = accepted.map { abs($0) }.max() ?? 0
    }
    public var progress: CaptureProgress {
        lock.lock()
        defer { lock.unlock() }
        return CaptureProgress(sampleCount: samples.count, level: min(1, level))
    }
    /// Read each captured sample once for VAD without removing the transcription audio.
    public func drainNewSamples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let result = Array(samples[readOffset...])
        readOffset = samples.count
        return result
    }
    public func take() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let result = samples
        samples = []
        readOffset = 0
        level = 0
        return result
    }
}

@MainActor
public final class MicrophoneSession {
    public enum State: Equatable { case idle, askingPermission, denied, recording, stopped, cancelled, failed }
    public private(set) var state: State = .idle
    public private(set) var audio: [Float] = []
    public private(set) var reachedCap = false
    public private(set) var stopReason: CaptureStopReason?
    private let engine: any MicrophoneEngine
    private let policy: any CaptureStopPolicy
    private let willStop: () -> Void
    public init(engine: any MicrophoneEngine, policy: any CaptureStopPolicy = ManualCaptureStopPolicy(),
                willStop: @escaping () -> Void = {}) {
        self.engine = engine
        self.policy = policy
        self.willStop = willStop
    }
    public var progress: CaptureProgress { engine.progress }
    public func start() async {
        guard state == .idle else { return }
        state = .askingPermission
        let allowed = await engine.requestPermission()
        guard state == .askingPermission else { return }
        guard allowed else { state = .denied; return }
        do { try engine.start(); policy.microphoneReady(); state = .recording }
        catch { _ = engine.stop(); state = .failed }
    }
    public func tick() {
        guard state == .recording else { return }
        reachedCap = progress.sampleCount >= CaptureBuffer.maximumSamples
        if reachedCap { stop(reason: .durationCap) }
        else if policy.shouldStop(progress) { stop(reason: policy.stopReason ?? .silence) }
    }
    public func stop(reason: CaptureStopReason = .userStop) {
        guard state == .recording else { return }
        stopReason = reason
        willStop()
        audio = engine.stop()
        state = .stopped
    }
    public func cancel() {
        _ = engine.stop()
        audio = []
        state = .cancelled
    }
}
