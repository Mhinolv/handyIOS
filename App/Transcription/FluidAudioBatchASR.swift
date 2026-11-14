import Foundation
import FluidAudio
import HandyKit

/// App-only adapter. Never call FluidAudio download or auto-recovery APIs here.
actor FluidAudioBatchASR: BatchASR {
    private let root: URL
    private let manifest: ModelManifest
    private var active: Task<ASRTranscription, Error>?

    init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true),
         manifest: ModelManifest = .production) {
        self.root = root
        self.manifest = manifest
    }

    func transcribe(_ audio: ASRAudio) async throws -> ASRTranscription {
        try Task.checkCancellation()
        guard active == nil else { throw HandyKit.ASRError.busy }
        let root = root
        let manifest = manifest
        let task = Task.detached { () throws -> ASRTranscription in
            let storage = LocalModelStorage(root: root)
            guard try await storage.validates(manifest, useMarker: true),
                  let asset = manifest.assets.first(where: { $0.repository == "FluidInference/parakeet-tdt-0.6b-v3-coreml" }) else {
                throw HandyKit.ASRError.modelsUnavailable
            }
            try Task.checkCancellation()
            let directory = root.appendingPathComponent(asset.repository).appendingPathComponent(asset.revision)
            let start = ContinuousClock.now
            let manager = AsrManager()
            do {
                // Keep the model value inside this scope so cleanup drops every reference.
                try await manager.loadModels(AsrModels.loadLocal(from: directory, version: .v3, encoderPrecision: .int8))
                try Task.checkCancellation()
                let loaded = ContinuousClock.now
                var state = try TdtDecoderState()
                let result = try await manager.transcribe(audio.samples, decoderState: &state)
                try Task.checkCancellation()
                let finished = ContinuousClock.now
                await manager.cleanup()
                return ASRTranscription(text: result.text, loadSeconds: seconds(start.duration(to: loaded)),
                                        runSeconds: seconds(loaded.duration(to: finished)))
            } catch {
                await manager.cleanup()
                throw error
            }
        }
        active = task
        defer { active = nil }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            task.cancel()
        }
    }

    func cancel() async {
        guard let task = active else { return }
        task.cancel()
        _ = await task.result
        // transcribe owns the slot until its suspended continuation returns.
    }

    func cleanup() async { await cancel() }
}

private func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
