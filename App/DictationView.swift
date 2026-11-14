import AVFoundation
import HandyKit
import SwiftUI

struct DictationView: View {
    let controller: DictationController
    @Environment(\.dismiss) private var dismiss
    private var coordinator: DictationCoordinator { controller.coordinator }


    var body: some View {
        DictationStatusView(state: controller.state, speechStatus: controller.speechStatus,
            vadError: controller.vadError, elapsed: controller.elapsed, level: controller.level,
            stopReason: controller.stopReason, recovery: coordinator.recovery,
            transcribing: coordinator.transcribing, text: coordinator.text, error: coordinator.error,
            reachedCap: controller.reachedCap, message: controller.message,
            stop: { controller.stop() }, cancel: { controller.cancel(); dismiss() },
            done: { dismiss() }, retry: { Task { await coordinator.retry() } })
        .interactiveDismissDisabled()
        .task { await controller.start() }
        .task(id: controller.state) {
            if controller.state == .stopped && controller.stopReason == .noSpeech {
                UIAccessibility.post(notification: .announcement, argument: "No speech detected.")
            }
            if controller.state == .stopped && controller.stopReason != .noSpeech && coordinator.recovery == nil {
                await coordinator.transcribe(samples: controller.audio)
                controller.releaseAudio()
            }
            if controller.state == .cancelled { dismiss() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let event = InterruptionHandler.event(notification) { controller.receive(event) }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let event = InterruptionHandler.event(notification) {
                controller.receive(controller.microphoneRunning ? event : .routeChanged(microphoneAvailable: false))
            }
        }
    }
}

/// Shared presentation for live dictation and inert DEBUG fixtures.
struct DictationStatusView: View {
    var state: MicrophoneSession.State
    var speechStatus = "Listening…"
    var vadError: String? = nil
    var elapsed = 12
    var level = 0.5
    var stopReason: CaptureStopReason? = nil
    var recovery: DictationRecovery? = nil
    var transcribing = false
    var text: String? = nil
    var error: String? = nil
    var reachedCap = false
    var message: String? = nil
    var stop: () -> Void = {}
    var cancel: () -> Void = {}
    var done: () -> Void = {}
    var retry: () -> Void = {}
    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var recoveryFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            switch state {
            case .idle, .askingPermission:
                if state == .idle { ProgressView("Starting…") }
            case .denied:
                Image(systemName: "mic.slash").font(.system(size: 56))
                Text("Microphone access is off.").font(.headline)
                Text("handyIOS needs the microphone to hear your dictation.")
                Button("Open Settings") {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                }
                Button("Cancel") { cancel() }.buttonStyle(.bordered)
            case .recording:
                Label("Recording", systemImage: "record.circle.fill").font(.headline).foregroundStyle(.red)
                Text(speechStatus)
                    .foregroundStyle(vadError == nil ? Color.secondary : Color.orange)
                if let error = vadError { Text(error).foregroundStyle(.orange) }
                Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                    .font(.system(size: 64)).monospacedDigit()
                    .accessibilityLabel("\(elapsed) seconds of 3 minutes")
                Text(elapsed >= 170 ? "\(180 - elapsed) seconds left" : "of 3:00")
                    .foregroundStyle(elapsed >= 170 ? Color.orange : Color.secondary)
                Image(systemName: "waveform", variableValue: level)
                    .font(.system(size: 48)).accessibilityHidden(true)
                ReturnHintView(compact: true)
                Button(action: stop) {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                    .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                Button("Cancel") { cancel() }.buttonStyle(.bordered)
            case .stopped:
                if stopReason == .noSpeech {
                    Image(systemName: "mic.slash").font(.system(size: 56))
                    Text("No speech detected.")
                    Button("Done") { done() }
                } else if let recovery = recovery {
                    Image(systemName: recovery.symbol).font(.system(size: 56))
                    Text(recovery.title).font(.headline).accessibilityFocused($recoveryFocused)
                    Text(recovery.body)
                    Button(recovery.action) { retry() }
                        .buttonStyle(.borderedProminent).disabled(transcribing)
                    Button("Discard") { cancel() }
                        .buttonStyle(.bordered).tint(.red)
                } else if let text = text {
                    ReturnHintView(title: "Text Ready")
                    Text(text).lineLimit(3).foregroundStyle(.secondary).padding()
                        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
                    Button("Done") { done() }.buttonStyle(.bordered)
                } else if let error = error {
                    Text(error)
                    Button("Done") { done() }.buttonStyle(.bordered)
                } else {
                    if reachedCap { Text("Reached the 3-minute limit.") }
                    ProgressView("Transcribing…")
                    Button("Cancel", action: cancel).buttonStyle(.bordered)
                }
            case .cancelled:
                EmptyView()
            case .failed:
                Text(message ?? "Could not start the microphone.")
                Button("Done") { cancel() }
            }
        }
        .multilineTextAlignment(.center).padding(32)
        .onChange(of: recovery) { _, reason in
            if reason != nil { recoveryFocused = true }
        }
    }
}
