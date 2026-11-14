#if DEBUG
import HandyKit
import SwiftUI
import UniformTypeIdentifiers

/// Import a local, headerless, little-endian Float32 sample at 16 kHz mono.
struct SampleTranscriptionSection: View {
    let isReady: Bool
    @State private var importing = false
    @State private var task: Task<Void, Never>?
    @State private var result: ASRTranscription?
    @State private var failed = false
    private let engine = FluidAudioBatchASR()

    var body: some View {
        Section("Diagnostics") {
            Button("Run Sample Transcription") { importing = true }
                .disabled(!isReady || task != nil)
            Text("Choose raw Float32 PCM, little-endian, 16 kHz mono. Maximum: 60 seconds.")
                .font(.caption)
            if task != nil {
                ProgressView("Transcribing…").accessibilityLabel("Transcribing")
                Button("Cancel") { task?.cancel() }.buttonStyle(.bordered)
            }
            if failed {
                Label("Transcription failed.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Button("Discard") { failed = false }
            }
            if let result {
                Text(result.text).textSelection(.enabled)
                LabeledContent("Load time", value: String(format: "%.2f s", result.loadSeconds))
                LabeledContent("Run time", value: String(format: "%.2f s", result.runSeconds))
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { selection in
            guard case let .success(url) = selection else { return }
            task = Task {
                defer { task = nil }
                result = nil
                failed = false
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= 60 * 16_000 * 4, size % 4 == 0 else {
                        throw HandyKit.ASRError.invalidSamples
                    }
                    let data = try Data(contentsOf: url)
                    let samples = data.withUnsafeBytes { bytes in
                        stride(from: 0, to: bytes.count, by: 4).map {
                            Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0, as: UInt32.self)))
                        }
                    }
                    result = try await engine.transcribe(ASRAudio(samples: samples))
                } catch is CancellationError {
                    result = nil
                } catch { failed = true }
            }
        }
        .onDisappear { task?.cancel() }
    }
}
#endif
