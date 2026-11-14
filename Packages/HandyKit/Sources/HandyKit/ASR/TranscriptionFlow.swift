import Foundation
import Observation

@MainActor
public protocol TranscriptionBackgroundTask: AnyObject {
    /// Return false when the system cannot grant background time.
    func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> Bool
    func end()
}

/// Owns the batch and its background lifetime. Expiry retains audio for a later retry.
@available(macOS 14.0, *)
@MainActor @Observable
public final class TranscriptionFlow {
    public private(set) var transcribing = false
    public private(set) var text: String?
    public private(set) var error: String?
    public private(set) var retainedAudio: [Float] = []
    public private(set) var recovery: DictationRecovery?
    private let asr: any BatchASR
    private let background: any TranscriptionBackgroundTask
    private let session: DictationSession
    private let id: UUID
    private var prepared = false
    private var terminal = false
    private var worker: Task<ASRTranscription, Error>?

    public init(asr: any BatchASR, background: any TranscriptionBackgroundTask,
                session: DictationSession, id: UUID) {
        self.asr = asr
        self.background = background
        self.session = session
        self.id = id
    }

    /// Call while the audio session still protects the app from suspension.
    public func prepare() {
        guard !prepared, !terminal else { return }
        prepared = true
        if !background.begin(expiration: { [weak self] in self?.expire() }) {
            expire()
        }
    }

    public func transcribe(samples: [Float]) async {
        guard !transcribing, text == nil else { return }
        if terminal && error == nil { return }
        retainedAudio = samples
        guard !terminal else { return }
        guard prepared else { finishFailure("Background time unavailable. Return to handyIOS to retry."); return }
        transcribing = true
        defer { transcribing = false }
        let asr = asr
        let task = Task { try await asr.transcribe(ASRAudio(samples: samples)) }
        worker = task
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
                Task { @MainActor [weak self] in self?.cancel() }
            }
            await asr.cleanup()
            worker = nil
            guard !terminal else { return }
            try Task.checkCancellation()
            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                finishFailure("No speech detected")
                return
            }
            guard try session.publish(text: result.text, requestID: id) else {
                finishFailure("The request is no longer available.")
                return
            }
            text = result.text
            retainedAudio = []
            terminal = true
            background.end()
        } catch {
            if Task.isCancelled { cancel() }
            await asr.cleanup()
            worker = nil
            if !terminal { finishFailure("Transcription failed. Return to handyIOS to retry.") }
        }
    }

    public func retain(samples: [Float], reason: DictationRecovery) {
        guard !transcribing, text == nil else { return }
        retainedAudio = samples
        recovery = reason
        terminal = true
        background.end()
        try? session.recover(requestID: id, message: reason.body)
    }

    public func retry() async {
        guard !transcribing, recovery != nil else { return }
        guard (try? session.retry(requestID: id)) == true else { cancel(); return }
        terminal = false
        prepared = false
        error = nil
        recovery = nil
        prepare()
        await transcribe(samples: retainedAudio)
    }

    public func finishWithoutTranscription() {
        guard !terminal else { return }
        terminal = true
        background.end()
    }

    public func cancel() {
        terminal = true
        worker?.cancel()
        retainedAudio = []
        recovery = nil
        error = nil
        _ = try? session.cancel(requestID: id)
        background.end()
        Task { await asr.cancel() }
    }

    private func expire() {
        guard !terminal else { return }
        worker?.cancel()
        finishFailure("Background time expired. Return to handyIOS to retry.")
        Task { await asr.cancel() }
    }

    private func finishFailure(_ message: String) {
        terminal = true
        error = message
        recovery = message.contains("Background") ? .expiry : .transcription
        try? session.setStopMessage(message, requestID: id)
        try? session.recover(requestID: id, message: message)
        background.end()
    }
}
