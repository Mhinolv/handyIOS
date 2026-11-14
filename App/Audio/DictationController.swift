import Foundation
import HandyKit
import Observation

@MainActor @Observable
final class DictationController: Identifiable {
    let id: UUID
    private let shared: DictationSession
    private let capture: MicrophoneSession
    private var task: Task<Void, Never>?
    var state: MicrophoneSession.State = .idle
    private var startedAt: ContinuousClock.Instant?
    var elapsed = 0
    var level: Double = 0
    var reachedCap = false
    var message: String?
    private(set) var audio: [Float] = []

    init(id: UUID, shared: DictationSession) {
        self.id = id
        self.shared = shared
        capture = MicrophoneSession(engine: AppMicrophoneEngine())
    }

    func start() async {
        guard state == .idle else { return }
        state = .askingPermission
        await capture.start()
        state = capture.state
        guard state == .recording else { return }
        do {
            guard try shared.startRecording(requestID: id) else { cancel(); return }
        } catch { fail(); return }
        startedAt = .now
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                self.update()
                if self.state != .recording { return }
            }
        }
    }

    private func update() {
        let duration = startedAt.map { Double($0.duration(to: .now).components.seconds) } ?? 0
        elapsed = min(180, Int(max(capture.progress.elapsed, duration)))
        if elapsed >= 180 {
            capture.stop()
            finish()
            reachedCap = true
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

    func stop() {
        guard state == .recording else { return }
        capture.stop()
        finish()
    }

    private func finish() {
        task?.cancel()
        reachedCap = capture.reachedCap
        audio = capture.audio
        state = .stopped
        do {
            guard try shared.finishCapture(requestID: id) else { fail(); return }
        } catch { fail() }
        // Issue #5 consumes audio here. Do not publish a fake transcript.
    }

    func cancel() {
        task?.cancel()
        capture.cancel()
        audio = []
        try? shared.cancel(requestID: id)
        state = .cancelled
    }

    func fail() {
        task?.cancel()
        capture.cancel()
        audio = []
        try? shared.fail(requestID: id)
        state = .failed
        message = "The microphone stopped. Return to your keyboard and try again."
    }
}
