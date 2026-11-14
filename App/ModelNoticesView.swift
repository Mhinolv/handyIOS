import HandyKit
import SwiftUI

struct ModelNoticesView: View {
    var body: some View {
        List {
            Section("FluidAudio") {
                Text("License: Apache-2.0")
                Text("Version: 0.18.3")
                license("FluidAudio")
            }
            Section("Parakeet TDT 0.6B v3") {
                Text("By NVIDIA")
                Text("License: CC-BY-4.0")
                Text("Core ML conversion: FluidInference")
                Text(ModelManifest.production.assets.first?.revision ?? "")
                    .font(.caption.monospaced()).textSelection(.enabled)
                license("Parakeet")
            }
            Section("Silero VAD") {
                Text("Silero Team")
                Text("License: MIT")
                license("Silero")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Acknowledgements")
    }

    private func license(_ name: String) -> some View {
        NavigationLink("View License") { LicenseTextView(name: name) }
    }
}

struct LicenseTextView: View {
    let name: String
    var body: some View {
        ScrollView {
            Text(text).font(.footnote.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle(name)
    }
    private var text: String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "License text is unavailable."
        }
        return text
    }
}
