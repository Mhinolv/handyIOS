import AVFoundation
import HandyKit
import SwiftUI
import UIKit

struct SetupView: View {
    static let privacyText = "Audio and text stay on this iPhone. handyIOS has no accounts and no analytics. It uses the network only to download the speech model."
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var confirmed = false
    @State private var microphone = AVAudioApplication.shared.recordPermission
    @State private var sample = ""
    @State private var settingsFailed = false

    var body: some View {
        List {
            Section {
                status("Add the Keyboard", done: confirmed)
                Text("In Settings, tap Keyboards, then turn on handyIOS.")
                Text("If needed, open Settings > General > Keyboard > Keyboards > Add New Keyboard, then select handyIOS.")
                confirmation
                settingsButton
            } header: { Text("Step 1") }
            Section {
                status("Allow Full Access", done: confirmed)
                Text("Full Access lets the keyboard and the app share your dictation on this iPhone. handyIOS sends nothing over the internet.")
                Text("Without Full Access, tap ABC to type with the manual keyboard.")
                confirmation
                settingsButton
            } header: { Text("Step 2") }
            Section {
                status("Allow the Microphone", done: microphone == .granted)
                Text("Only the app records. The keyboard never does.")
                if microphone == .denied {
                    Text("Microphone access is off. Open Settings to allow it, or tap ABC in the keyboard to type.")
                    settingsButton
                } else if microphone != .granted {
                    Button("Allow") {
                        Task { @MainActor in
                            _ = await AVAudioApplication.requestRecordPermission()
                            refresh()
                        }
                    }
                }
            } header: { Text("Step 3") }
            Section {
                TextField("Tap here, then tap the globe key", text: $sample)
                    .accessibilityLabel("Try the keyboard")
                Text("Tap ABC for letters. Tap the mic to return to dictation.")
            } header: { Text("Step 4: Try It") } footer: {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Self.privacyText)
                    Text("Password and phone number fields use the iPhone keyboard.")
                }
            }
            if settingsFailed {
                Text("Open Settings manually, then select General > Keyboard > Keyboards > handyIOS.")
            }
        }
        .navigationTitle("Set Up Keyboard")
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .task {
            // The keyboard can confirm setup while the Try It field has focus.
            while !Task.isCancelled {
                refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    @ViewBuilder private var confirmation: some View {
        if !confirmed { Text("Not confirmed yet. Open the keyboard once.").foregroundStyle(.secondary) }
    }

    private var settingsButton: some View {
        Button("Open Settings") {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url) { accepted in settingsFailed = !accepted }
        }
    }

    private func status(_ title: String, done: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not confirmed")
    }

    private func refresh() {
        confirmed = UserDefaults(suiteName: HandyConfiguration.appGroupIdentifier)?
            .bool(forKey: HandyConfiguration.keyboardSeenWithFullAccessKey) ?? false
        microphone = AVAudioApplication.shared.recordPermission
    }
}
