import HandyKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text(HandyConfiguration.displayName)
                .font(.largeTitle)
            Text("Local dictation")
                .foregroundStyle(.secondary)
            Text("Dictation is not available yet.")
        }
        .padding()
    }
}
