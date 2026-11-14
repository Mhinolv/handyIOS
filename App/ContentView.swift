import HandyKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model = ModelDownloadManager.appDefault()

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    NavigationLink {
                        ModelDownloadView(model: model)
                    } label: {
                        LabeledContent("Model", value: model.state == .ready ? "Ready" : "Not Downloaded")
                    }
                }
                Section("About") {
                    NavigationLink { ModelNoticesView() } label: {
                        Label("Acknowledgements", systemImage: "doc.text")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("handyIOS")
        }
        .task { await model.refresh() }
    }
}
