import Foundation

/// An in-memory batch. The caller owns and deletes any source audio file.
public struct ASRAudio: Sendable, Equatable {
    public let samples: [Float]
    public init(samples: [Float], sampleRate: Int = 16_000, channels: Int = 1) throws {
        guard sampleRate == 16_000, channels == 1 else { throw ASRError.unsupportedFormat }
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else {
            throw ASRError.invalidSamples
        }
        self.samples = samples
    }
}

public enum ASRError: Error, Equatable, Sendable {
    case unsupportedFormat, invalidSamples, busy, modelsUnavailable
}

public struct ASRTranscription: Sendable, Equatable {
    public let text: String
    public let loadSeconds: Double
    public let runSeconds: Double
    public init(text: String, loadSeconds: Double, runSeconds: Double) {
        self.text = text
        self.loadSeconds = loadSeconds
        self.runSeconds = runSeconds
    }
}

public protocol BatchASR: Sendable {
    func transcribe(_ audio: ASRAudio) async throws -> ASRTranscription
    /// Cancel the current batch and wait until its resources are released.
    func cancel() async
    func cleanup() async
}
