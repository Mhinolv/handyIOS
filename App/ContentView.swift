import HandyKit
import SwiftUI

struct ContentView: View {
    @AppStorage(SilenceDelay.storageKey) private var silenceSeconds = SilenceDelay.defaultValue.rawValue
    @StateObject private var model = ModelDownloadManager.appDefault()

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
            }
            .listStyle(.insetGrouped)
            .navigationTitle("handyIOS")
        }
        .task { await model.refresh() }
    }
}
