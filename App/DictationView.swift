import AVFoundation
import HandyKit
import SwiftUI

struct DictationView: View {
    let controller: DictationController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showsTranscribing = false

    var body: some View {
        VStack(spacing: 24) {
            switch controller.state {
            case .idle, .askingPermission:
                if controller.state == .idle { ProgressView("Starting…") }
            case .denied:
                Image(systemName: "mic.slash").font(.system(size: 56))
                Text("Microphone access is off.").font(.headline)
                Text("handyIOS needs the microphone to hear your dictation.")
                Button("Open Settings") {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                }
                Button("Cancel") { controller.cancel(); dismiss() }.buttonStyle(.bordered)
            case .recording:
                Label("Recording", systemImage: "record.circle.fill").font(.headline).foregroundStyle(.red)
                Text(controller.speechStatus)
                    .foregroundStyle(controller.vadError == nil ? Color.secondary : Color.orange)
                if let error = controller.vadError { Text(error).foregroundStyle(.orange) }
                Text(String(format: "%02d:%02d", controller.elapsed / 60, controller.elapsed % 60))
                    .font(.system(size: 64)).monospacedDigit()
                    .accessibilityLabel("\(controller.elapsed) seconds of 3 minutes")
                Text(controller.elapsed >= 170 ? "\(180 - controller.elapsed) seconds left" : "of 3:00")
                    .foregroundStyle(controller.elapsed >= 170 ? Color.orange : Color.secondary)
                Image(systemName: "waveform", variableValue: controller.level)
                    .font(.system(size: 48)).accessibilityHidden(true)
                ReturnHintView(compact: true)
                Button("Stop", systemImage: "stop.fill") { controller.stop() }
                    .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                Button("Cancel") { controller.cancel(); dismiss() }.buttonStyle(.bordered)
            case .stopped:
                if controller.stopReason == .noSpeech {
                    Image(systemName: "mic.slash").font(.system(size: 56))
                    Text("No speech detected.")
                    Button("Done") { dismiss() }
                } else if controller.reachedCap && !showsTranscribing {
                    Text("Reached the 3-minute limit.")
                } else {
                    Text(controller.message ?? "Audio captured.")
                    Text("Transcription is not available yet.").foregroundStyle(.secondary)
                    Button("Done") { controller.cancel(); dismiss() }
                }
            case .cancelled:
                EmptyView()
            case .failed:
                Text(controller.message ?? "Could not start the microphone.")
                Button("Done") { controller.cancel(); dismiss() }
            }
        }
        .multilineTextAlignment(.center).padding(32)
        .interactiveDismissDisabled()
        .task { await controller.start() }
        .task(id: controller.state) {
            if controller.state == .stopped && controller.stopReason == .noSpeech {
                UIAccessibility.post(notification: .announcement, argument: "No speech detected.")
            }
            if controller.state == .stopped && controller.reachedCap {
                try? await Task.sleep(for: .seconds(2))
                showsTranscribing = true
            }
            if controller.state == .cancelled { dismiss() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            if controller.state == .recording { controller.fail() }
        }
    }
}
