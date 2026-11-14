import HandyKit
import SwiftUI

@main
struct HandyIOSApp: App {
    @State private var showsReturnHint = false
    @State private var handoffError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if showsReturnHint { ReturnHintView() }
                else { ContentView() }
            }
            .onOpenURL { url in
                guard let id = KeyboardHandoff.requestID(from: url) else { return }
                do {
                    let session = DictationSession(storage: try AppGroupSessionStorage())
                    guard try KeyboardHandoff.publishFakeResult(session: session, requestID: id) else {
                        handoffError = "The request is no longer available. Return to your keyboard and try again."
                        return
                    }
                    showsReturnHint = true
                } catch {
                    handoffError = "Handy could not read the shared request. Return to your keyboard and try again."
                }
            }
            .alert("Could Not Complete Request", isPresented: Binding(
                get: { handoffError != nil },
                set: { if !$0 { handoffError = nil } }
            )) {
                Button("OK") { handoffError = nil }
            } message: {
                Text(handoffError ?? "")
            }
        }
    }
}
