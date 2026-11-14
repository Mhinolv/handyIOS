import HandyKit
import SwiftUI

struct SilenceSettingsView: View {
    @AppStorage(SilenceDelay.storageKey) private var seconds = SilenceDelay.defaultValue.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Auto-Stop", selection: $seconds) {
                    ForEach(SilenceDelay.allCases, id: \.rawValue) { delay in
                        Text(delay.title).tag(delay.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("Recording stops when you stop speaking for this long. If you do not speak for 10 seconds after recording starts, it stops.")
            }
        }
        .navigationTitle("Auto-Stop")
    }
}
