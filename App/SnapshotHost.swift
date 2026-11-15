#if DEBUG
import HandyKit
import SwiftUI

/// Keep this list identical to scripts/snapshot.sh.
enum SnapshotState: String {
    case setup
    case modelNotDownloaded = "model-not-downloaded", modelDownloading = "model-downloading"
    case modelFailed = "model-failed", modelReady = "model-ready"
    case listening, transcribing, textReady = "text-ready", recovery
    case lastResult = "last-result", silenceSettings = "silence-settings", replacements, licenses
    case keyboardIdle = "keyboard-idle", keyboardOpening = "keyboard-opening"
    case keyboardListening = "keyboard-listening", keyboardInserted = "keyboard-inserted"
    case keyboardFullAccessOff = "keyboard-full-access-off", keyboardABC = "keyboard-abc"
    case denied, listeningLastSeconds = "listening-last-10", noSpeech = "no-speech"
    case vadFailure = "vad-failure", failed
    case recoveryRoute = "recovery-route", recoveryExpiry = "recovery-expiry"
    case recoveryTranscription = "recovery-transcription"
    case setupDone = "setup-done", replacementsEmpty = "replacements-empty"
    case replacementsEdit = "replacements-edit", lastResultCopied = "last-result-copied"
    case keyboardChip = "keyboard-chip", keyboardRecovery = "keyboard-recovery"

    static var requested: SnapshotState? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-HandySnapshotState"),
              arguments.indices.contains(index + 1) else { return nil }
        return SnapshotState(rawValue: arguments[index + 1])
    }
}

struct SnapshotHost: View {
    let state: SnapshotState
    private let sample = "Meet me at the library at three. Bring the notes for our next project."
    var body: some View {
        NavigationStack {
            switch state {
            case .setup, .setupDone: SetupView()
            case .modelNotDownloaded, .modelDownloading, .modelFailed, .modelReady:
                ModelDownloadView(model: ModelDownloadManager(manifest: .production,
                    transport: SnapshotTransport(), storage: SnapshotModelStorage()), snapshotState: modelState)
            case .listening: DictationStatusView(state: .recording)
            case .transcribing: DictationStatusView(state: .stopped, transcribing: true)
            case .textReady: DictationStatusView(state: .stopped, text: sample)
            case .recovery: DictationStatusView(state: .stopped, recovery: .interruption)
            case .recoveryRoute: DictationStatusView(state: .stopped, recovery: .route)
            case .recoveryExpiry: DictationStatusView(state: .stopped, recovery: .expiry)
            case .recoveryTranscription: DictationStatusView(state: .stopped, recovery: .transcription)
            case .denied: DictationStatusView(state: .denied)
            case .listeningLastSeconds: DictationStatusView(state: .recording, speechStatus: "Hearing you", elapsed: 172)
            case .noSpeech: DictationStatusView(state: .stopped, stopReason: .noSpeech)
            case .vadFailure:
                DictationStatusView(state: .recording,
                    speechStatus: "Auto-stop is not available. Tap Stop when you finish.",
                    vadError: "The speech detector stopped.")
            case .failed: DictationStatusView(state: .failed)
            case .lastResult, .lastResultCopied:
                List { LastResultView(snapshot: lastResult, snapshotCopied: state == .lastResultCopied) }
                    .navigationTitle("handyIOS")
            case .silenceSettings:
                SilenceSettingsView().defaultAppStorage(UserDefaults(suiteName: "HandySnapshot")!)
            case .replacements, .replacementsEdit:
                ReplacementSettingsView(model: ReplacementSettingsModel(storage: SnapshotReplacements()),
                    snapshotSheet: state == .replacementsEdit)
            case .replacementsEmpty:
                ReplacementSettingsView(model: ReplacementSettingsModel(storage: SnapshotReplacements(rules: [])))
            case .licenses: ModelNoticesView()
            default:
                VStack(alignment: .leading) {
                    Text("Try the keyboard").font(.headline).padding()
                    Text(state == .keyboardInserted ? sample : "Your text appears here.").padding()
                    Spacer()
                    SnapshotKeyboard(name: state.rawValue).frame(height: KeyboardLayout.height)
                        .background(Color(uiColor: .secondarySystemBackground))
                }.navigationTitle("Keyboard")
            }
        }
        .environment(HandoffModel())
        .allowsHitTesting(false)
    }

    private var modelState: ModelDownloadState {
        switch state {
        case .modelDownloading: .downloading(received: 300_000_000, total: ModelManifest.production.totalBytes)
        case .modelFailed: .stopped
        case .modelReady: .ready
        default: .notDownloaded
        }
    }
    private var lastResult: LastResult? {
        let session = DictationSession(storage: SnapshotSessionStorage())
        guard let request = try? session.request() else { return nil }
        _ = try? session.startRecording(requestID: request.id)
        _ = try? session.finishCapture(requestID: request.id)
        _ = try? session.publish(text: sample, requestID: request.id)
        return try? session.lastResult()
    }
}

private struct SnapshotKeyboard: UIViewControllerRepresentable {
    let name: String
    func makeUIViewController(context: Context) -> KeyboardViewController {
        let controller = KeyboardViewController()
        controller.snapshotName = name
        return controller
    }
    func updateUIViewController(_ controller: KeyboardViewController, context: Context) {}
}

private final class SnapshotSessionStorage: SessionStorage {
    private var data: Data?
    func transaction<T>(_ body: (inout Data?) throws -> T) throws -> T { try body(&data) }
}
private struct SnapshotTransport: ModelTransport {
    func download(_ asset: ModelAsset, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        throw ModelDownloadError.http
    }
}
private struct SnapshotModelStorage: ModelStorage {
    func availableBytes() async throws -> Int64 { 12_000_000_000 }
    func validates(_ asset: ModelAsset) async throws -> Bool { false }
    func install(_ temporary: URL, asset: ModelAsset) async throws {}
}
private struct SnapshotReplacements: ReplacementRuleStorage {
    var rules = [ReplacementRule(phrase: "handy ios", replacement: "handyIOS")]
    func load() -> [ReplacementRule] { rules }
    func save(_ rules: [ReplacementRule]) throws {}
}
#endif
