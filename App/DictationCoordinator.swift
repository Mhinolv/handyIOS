import Foundation
import HandyKit
import Observation

@MainActor @Observable
final class DictationCoordinator {
    private(set) var transcribing = false
    private(set) var text: String?
    private(set) var error: String?
    private let asr: any BatchASR
    init(asr: any BatchASR = FluidAudioBatchASR()) { self.asr = asr }

    func transcribe(samples: [Float], session: DictationSession, id: UUID) async {
        guard !transcribing, text == nil, error == nil else { return }
        transcribing = true
        defer { transcribing = false }
        do {
            let result = try await asr.transcribe(ASRAudio(samples: samples))
            await asr.cleanup()
            try Task.checkCancellation()
            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                try session.setStopMessage("No speech detected", requestID: id)
                _ = try session.fail(requestID: id)
                error = "No speech detected"
                return
            }
            guard try session.publish(text: result.text, requestID: id) else {
                error = "The request is no longer available."
                return
            }
            text = result.text
        } catch {
            await asr.cleanup()
            try? session.setStopMessage("Transcription failed. Try again.", requestID: id)
            _ = try? session.fail(requestID: id)
            self.error = "Transcription failed. Return to your keyboard and try again."
        }
    }
}
