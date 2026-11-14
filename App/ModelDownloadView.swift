import HandyKit
import SwiftUI

struct ModelDownloadView: View {
    @ObservedObject var model: ModelDownloadManager

    var body: some View {
        List {
            Section {
                Text("Parakeet TDT 0.6B v3").font(.headline)
                Text("Speech model. Runs on this iPhone.").font(.subheadline).foregroundStyle(.secondary)
                LabeledContent("Download size", value: model.manifest.isConfigured ? bytes(model.manifest.totalBytes) : "Not configured")
                LabeledContent("Available", value: bytes(model.availableBytes))
            }
            Section {
                status
                if case .downloading = model.state {
                    Button { model.cancel() } label: {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else if model.state != .checking && model.state != .ready {
                    Button(model.state == .notDownloaded ? "Download" : "Retry") { model.start() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(!model.manifest.isConfigured)
                }
            }
            Section("Acknowledgements") {
                Text("Parakeet TDT 0.6B v3: NVIDIA. Licensed under Creative Commons Attribution 4.0 (CC BY 4.0). Core ML conversion: FluidInference.")
                Text("CC BY 4.0 permits use and adaptation with attribution. License: https://creativecommons.org/licenses/by/4.0/")
                    .foregroundStyle(.secondary)
                Text("Silero VAD: Silero Team. Licensed under the MIT License. Core ML conversion: FluidInference.")
                Text("Model sources: FluidInference/parakeet-tdt-0.6b-v3-coreml and FluidInference/silero-vad-coreml on Hugging Face. File set: FluidAudio v0.18.3.")
                    .foregroundStyle(.secondary)
                DisclosureGroup("MIT License") {
                    Text("""
                    Copyright Silero Team

                    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

                    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

                    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                    """)
                    .font(.footnote)
                    .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Model")
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .notDownloaded: EmptyView()
        case let .downloading(received, total):
            ProgressView(value: Double(received), total: Double(max(1, total)))
                .accessibilityLabel("Download progress")
                .accessibilityValue("\(Int(Double(received) / Double(max(1, total)) * 100)) percent")
            Text("\(bytes(received)) of \(bytes(total))")
        case .checking:
            ProgressView("Checking files…")
        case .ready:
            Label("Ready. Works offline.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .stopped: error("Download stopped.")
        case .corrupt: error("A file did not pass the check. Retry downloads it again.")
        case let .lowSpace(missing): error("Not enough space. Free up \(bytes(missing)), then tap Retry.")
        case .configurationRequired: error("The model file list needs verified source revisions before download.")
        }
    }

    private func error(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    }
    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
