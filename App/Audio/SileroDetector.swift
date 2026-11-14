import CoreML
import FluidAudio
import Foundation
import HandyKit

/// Loads only the pinned model installed by the app. No ModelHub or SDK download calls.
actor SileroDetector: VoiceActivityDetecting {
    private let root: URL
    private let manifest: ModelManifest
    private var manager: VadManager?
    private var stream = VadStreamState.initial()
    private var pending: [Float] = []
    private var processedSamples = 0

    init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true),
         manifest: ModelManifest = .production) {
        self.root = root
        self.manifest = manifest
    }

    func reset() async throws {
        manager = nil
        pending = []
        stream = .initial()
        processedSamples = 0
        let storage = LocalModelStorage(root: root)
        guard try await storage.validates(manifest, useMarker: true),
              let asset = manifest.assets.first(where: { $0.repository == "FluidInference/silero-vad-coreml" }) else {
            throw DetectorError.modelUnavailable
        }
        try Task.checkCancellation()
        let modelURL = root.appendingPathComponent(asset.repository)
            .appendingPathComponent(asset.revision)
            .appendingPathComponent("silero-vad-unified-256ms-v6.2.1.mlmodelc", isDirectory: true)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        // The preloaded-model initializer cannot fetch missing model files.
        manager = VadManager(vadModel: model)
    }

    func process(_ samples: [Float]) async throws -> [SpeechProbability] {
        guard let manager else { throw DetectorError.modelUnavailable }
        pending.append(contentsOf: samples)
        var frames: [SpeechProbability] = []
        var offset = 0
        while pending.count - offset >= 4096 {
            try Task.checkCancellation()
            let chunk = Array(pending[offset..<(offset + 4096)])
            let result = try await manager.processStreamingChunk(chunk, state: stream)
            guard result.probability.isFinite, (0...1).contains(result.probability) else {
                throw DetectorError.invalidProbability
            }
            stream = result.state
            offset += 4096
            processedSamples += 4096
            // Ignore SDK segment events and padding. Use the end of the raw speech frame.
            frames.append(SpeechProbability(probability: result.probability,
                                            elapsed: Double(processedSamples) / 16_000))
        }
        pending.removeFirst(offset)
        return frames
    }

    private enum DetectorError: LocalizedError {
        case modelUnavailable, invalidProbability
        var errorDescription: String? {
            switch self {
            case .modelUnavailable: return "The local voice activity model is not available."
            case .invalidProbability: return "The voice activity model returned an invalid probability."
            }
        }
    }
}
