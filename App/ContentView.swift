import HandyKit
import SwiftUI

struct ContentView: View {
    @AppStorage(SilenceDelay.storageKey) private var silenceSeconds = SilenceDelay.defaultValue.rawValue
    @StateObject private var model = ModelDownloadManager.appDefault()

    @AppStorage("hasShownKeyboardSetup") private var hasShownSetup = false
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            List {
                Section("Settings") {
                    NavigationLink {
                        SilenceSettingsView()
                    } label: {
                        LabeledContent {
                            Text((SilenceDelay(rawValue: silenceSeconds) ?? .two).title)
                        } label: {
                            Label("Auto-Stop", systemImage: "waveform.badge.minus")
                        }
                    }
                }
                Section("Status") {
                    NavigationLink {
                        ModelDownloadView(model: model)
                    } label: {
                        LabeledContent("Model", value: model.state == .ready ? "Ready" : "Not Downloaded")
                    }
                }
                Section("Keyboard") {
                    Button { showSetup = true } label: {
                        Label("Keyboard", systemImage: "keyboard")
                    }
                }
                Section("About") {
                    NavigationLink("Privacy") {
                        List { Text(SetupView.privacyText) }.navigationTitle("Privacy")
                    }
                    NavigationLink { ModelNoticesView() } label: {
                        Label("Acknowledgements", systemImage: "doc.text")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("handyIOS")
        }
        .sheet(isPresented: $showSetup) {
            NavigationStack {
                SetupView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showSetup = false }
                    } }
            }
        }
        .onAppear {
            if !hasShownSetup {
                hasShownSetup = true
                showSetup = true
            }
        }
        .task { await model.refresh() }
    }
}
