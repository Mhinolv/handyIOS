import Foundation
import HandyKit
import Observation

@MainActor @Observable
final class DictationController: Identifiable {
    let id: UUID
    let shared: DictationSession
    private let capture: MicrophoneSession
    private let engine: AppMicrophoneEngine
    private let detector: any VoiceActivityDetecting
    private(set) var vadError: String?
    private(set) var hasSpeech = false
    let silencePolicy: SilenceStopPolicy
    private(set) var stopReason: CaptureStopReason?
    var speechStatus: String {
        if vadError != nil { return "Auto-stop is not available. Tap Stop when you finish." }
        if silencePolicy.delay == .off { return "Tap Stop when you finish." }
        return hasSpeech ? "Hearing you" : "Listening…"
    }
    private var task: Task<Void, Never>?
    var state: MicrophoneSession.State = .idle
    private var startedAt: ContinuousClock.Instant?
    var elapsed = 0
    var level: Double = 0
    var reachedCap = false
    var message: String?
    private(set) var audio: [Float] = []

    init(id: UUID, shared: DictationSession, silencePolicy: SilenceStopPolicy? = nil,
         detector: any VoiceActivityDetecting = SileroDetector()) {
        self.id = id
        self.shared = shared
        let policy = silencePolicy ?? SilenceStopPolicy(delay: .stored())
        self.silencePolicy = policy
        self.detector = detector
        let engine = AppMicrophoneEngine()
        self.engine = engine
        capture = MicrophoneSession(engine: engine, policy: policy)
    }

    func start() async {
        guard state == .idle else { return }
        state = .askingPermission
        do { try await detector.reset() }
        catch { reportVADError(error) }
        guard state == .askingPermission else { return }
        await capture.start()
        state = capture.state
        guard state == .recording else {
            if state == .denied || state == .failed {
                _ = try? shared.fail(requestID: id)
            }
            return
        }
        do {
            guard try shared.startRecording(requestID: id) else { cancel(); return }
        } catch { fail(); return }
        startedAt = .now
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                await self.update()
                if self.state != .recording { return }
            }
        }
    }

    private func update() async {
        let samples = engine.drainVADSamples()
        if vadError == nil {
            do {
                let frames = try await detector.process(samples)
                guard state == .recording else { return }
                for frame in frames { silencePolicy.receive(frame) }
                hasSpeech = silencePolicy.hasSpeech
            } catch {
                guard state == .recording else { return }
                reportVADError(error)
            }
        }
        guard state == .recording else { return }
        let duration = startedAt.map { Double($0.duration(to: .now).components.seconds) } ?? 0
        elapsed = min(180, Int(max(capture.progress.elapsed, duration)))
        if elapsed >= Int(DictationSession.maximumDictationDuration - DictationSession.captureStopMargin) {
            capture.stop(reason: .durationCap)
            finish(atCap: true)
            return
        }
        level = Double(capture.progress.level)
        capture.tick()
        if capture.state == .stopped { finish(); return }
        do {
            let snapshot = try shared.snapshot()
            guard snapshot.request?.id == id else { cancel(); return }
            if snapshot.stopRequested { stop(); return }
        } catch { fail(); return }
    }

    private func reportVADError(_ error: Error) {
        let text = error.localizedDescription
        silencePolicy.detectorFailed(text)
        vadError = text
    }

    func stop() {
        guard state == .recording else { return }
        capture.stop()
        finish()
    }

    private func finish(atCap: Bool = false) {
        task?.cancel()
        reachedCap = atCap || capture.reachedCap
        stopReason = capture.stopReason
        audio = capture.audio
        if stopReason == .noSpeech {
            audio = []
            capture.cancel()
            message = "No speech detected."
            state = .stopped
            try? shared.setStopMessage("No speech detected", requestID: id)
            _ = try? shared.fail(requestID: id)
            return
        }
        state = .stopped
        do {
            if try !shared.finishCapture(requestID: id) {
                message = "Audio captured. The shared request is no longer available."
            }
        } catch {
            message = "Audio captured. Handy could not update the shared request."
        }
        let copy = reachedCap ? "Reached the 3-minute limit." : "Stopped after silence."
        if stopReason == .silence || reachedCap { try? shared.setStopMessage(copy, requestID: id) }
    }

    func releaseAudio() { audio = []; capture.cancel() }

    func cancel() {
        task?.cancel()
        capture.cancel()
        audio = []
        try? shared.cancel(requestID: id)
        state = .cancelled
    }

    func fail() {
        if state == .recording {
            capture.stop(reason: .interruption)
            stopReason = .interruption
        }
        task?.cancel()
        capture.cancel()
        audio = []
        try? shared.setStopMessage("The microphone stopped. Try again.", requestID: id)
        try? shared.fail(requestID: id)
        state = .failed
        message = "The microphone stopped. Return to your keyboard and try again."
    }
}
