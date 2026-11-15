import Foundation
import HandyKit
import Observation

@MainActor @Observable
final class DictationController: Identifiable {
    let id: UUID
    let shared: DictationSession
    let coordinator: DictationCoordinator
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
    private var heartbeatTask: Task<Void, Never>?
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
        let coordinator = DictationCoordinator(asr: FluidAudioBatchASR(),
            background: AppTranscriptionBackgroundTask(), session: shared, id: id)
        self.coordinator = coordinator
        capture = MicrophoneSession(engine: engine, policy: policy, willStop: { coordinator.prepare() })
    }

    private var tag: String { HandyLog.short(id) }

    func start() async {
        guard state == .idle else {
            HandyLog.capture.notice("start skipped: request \(self.tag, privacy: .public) state \(String(describing: self.state), privacy: .public)")
            return
        }
        HandyLog.capture.notice("start: request \(self.tag, privacy: .public)")
        state = .askingPermission
        do { try await detector.reset() }
        catch { reportVADError(error) }
        guard state == .askingPermission else {
            HandyLog.capture.notice("start ended: request \(self.tag, privacy: .public) left permission step as \(String(describing: self.state), privacy: .public)")
            return
        }
        await capture.start()
        state = capture.state
        guard state == .recording else {
            HandyLog.capture.error("start failed: request \(self.tag, privacy: .public) microphone \(String(describing: self.state), privacy: .public)")
            if state == .denied || state == .failed {
                _ = try? shared.fail(requestID: id)
            }
            return
        }
        do {
            guard try shared.startRecording(requestID: id) else {
                let slot = try? shared.snapshot()
                HandyLog.session.error("startRecording false: request \(self.tag, privacy: .public), slot \(HandyLog.short(slot?.request?.id), privacy: .public) state \(slot?.state.rawValue ?? "unreadable", privacy: .public)")
                cancel(reason: "startRecording returned false")
                return
            }
        } catch {
            fail(reason: "startRecording threw: \(error)")
            return
        }
        HandyLog.capture.notice("recording: request \(self.tag, privacy: .public)")
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                let slotID = try? self.shared.snapshot().request?.id
                guard slotID == self.id else {
                    self.cancel(reason: "heartbeat: slot holds \(HandyLog.short(slotID))")
                    return
                }
                try? self.shared.heartbeat(requestID: self.id)
            }
        }
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
            HandyLog.capture.notice("stop: request \(self.tag, privacy: .public) reason durationCap")
            capture.stop(reason: .durationCap)
            finish(atCap: true)
            return
        }
        level = Double(capture.progress.level)
        capture.tick()
        if capture.state == .stopped {
            HandyLog.capture.notice("stop: request \(self.tag, privacy: .public) reason \(String(describing: self.capture.stopReason), privacy: .public)")
            finish()
            return
        }
        do {
            let snapshot = try shared.snapshot()
            guard snapshot.request?.id == id else {
                cancel(reason: "tick: slot holds \(HandyLog.short(snapshot.request?.id))")
                return
            }
            if snapshot.stopRequested {
                HandyLog.capture.notice("stop: request \(self.tag, privacy: .public) reason keyboard stop")
                stop()
                return
            }
        } catch {
            fail(reason: "tick: shared request unreadable: \(error)")
            return
        }
    }

    private func reportVADError(_ error: Error) {
        let text = error.localizedDescription
        HandyLog.capture.error("auto-stop unavailable: request \(self.tag, privacy: .public): \(text, privacy: .public)")
        silencePolicy.detectorFailed(text)
        vadError = text
    }

    func stop() {
        guard state == .recording else { return }
        HandyLog.capture.notice("stop: request \(self.tag, privacy: .public) reason user or keyboard")
        capture.stop()
        finish()
    }

    private func finish(atCap: Bool = false) {
        task?.cancel()
        reachedCap = atCap || capture.reachedCap
        stopReason = capture.stopReason
        audio = capture.audio
        if stopReason == .noSpeech {
            HandyLog.capture.notice("finish: request \(self.tag, privacy: .public) no speech, no transcription")
            coordinator.finishWithoutTranscription()
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
                HandyLog.session.error("finishCapture false: request \(self.tag, privacy: .public) not in slot")
                message = "Audio captured. The shared request is no longer available."
            } else {
                HandyLog.session.notice("finishCapture: request \(self.tag, privacy: .public) transcribing")
            }
        } catch {
            HandyLog.session.error("finishCapture failed: request \(self.tag, privacy: .public): \(String(describing: error), privacy: .public)")
            message = "Audio captured. Handy could not update the shared request."
        }
        let copy = reachedCap ? "Reached the 3-minute limit." : "Stopped after silence."
        if coordinator.error == nil && (stopReason == .silence || reachedCap) {
            try? shared.setStopMessage(copy, requestID: id)
        }
    }

    func releaseAudio() { audio = []; capture.cancel() }

    func cancel(reason: String = "user cancel") {
        HandyLog.capture.notice("cancel: request \(self.tag, privacy: .public) state \(String(describing: self.state), privacy: .public) reason \(reason, privacy: .public)")
        heartbeatTask?.cancel()
        coordinator.cancel()
        task?.cancel()
        capture.cancel()
        audio = []
        _ = try? shared.cancel(requestID: id)
        state = .cancelled
    }

    var microphoneRunning: Bool { engine.isRunning }

    func receive(_ event: CaptureRecoveryEvent) {
        guard state == .recording, let reason = event.recovery else { return }
        HandyLog.capture.error("stop: request \(self.tag, privacy: .public) reason interruption \(String(describing: reason), privacy: .public)")
        capture.stop(reason: .interruption)
        task?.cancel()
        stopReason = .interruption
        audio = capture.audio
        state = .stopped
        coordinator.retain(samples: audio, reason: reason)
        releaseAudio()
    }

    func fail(reason: String) {
        HandyLog.capture.error("fail: request \(self.tag, privacy: .public) state \(String(describing: self.state), privacy: .public) reason \(reason, privacy: .public)")
        if state == .recording {
            capture.stop(reason: .interruption)
            stopReason = .interruption
        }
        coordinator.finishWithoutTranscription()
        task?.cancel()
        capture.cancel()
        audio = []
        try? shared.setStopMessage("The microphone stopped. Try again.", requestID: id)
        _ = try? shared.fail(requestID: id)
        state = .failed
        message = "The microphone stopped. Return to your keyboard and try again."
    }
}
