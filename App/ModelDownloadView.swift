import HandyKit
import SwiftUI

struct ModelDownloadView: View {
    @ObservedObject var model: ModelDownloadManager

    #if DEBUG
    var snapshotState: ModelDownloadState? = nil
    #endif
    private var state: ModelDownloadState {
        #if DEBUG
        if let snapshotState { return snapshotState }
        #endif
        return model.state
    }

    private var availableBytes: Int64 {
        #if DEBUG
        if snapshotState != nil { return 12_000_000_000 }
        #endif
        return model.availableBytes
    }

    var body: some View {
        List {
            Section {
                Text("Parakeet TDT 0.6B v3").font(.headline)
                Text("Speech model. Runs on this iPhone.").font(.subheadline).foregroundStyle(.secondary)
                LabeledContent("Download size", value: model.manifest.isConfigured ? bytes(model.manifest.totalBytes) : "Not configured")
                LabeledContent("Available", value: bytes(availableBytes))
            }
            Section {
                status
                if case .downloading = state {
                    Button { model.cancel() } label: {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else if state != .checking && state != .ready {
                    Button { model.start() } label: {
                        Text(state == .notDownloaded ? "Download" : "Retry").frame(maxWidth: .infinity)
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(!model.manifest.isConfigured)
                }
            }
            #if DEBUG
            if snapshotState == nil { SampleTranscriptionSection(isReady: state == .ready) }
            #endif
            Section {
                NavigationLink("Acknowledgements") { ModelNoticesView() }
            }
        }
        .navigationTitle("Model")
    }

    @ViewBuilder private var status: some View {
        switch state {
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
