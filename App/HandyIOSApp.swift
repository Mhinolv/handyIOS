import HandyKit
import SwiftUI

@main
struct HandyIOSApp: App {
    @State private var dictation: DictationController?
    @State private var handoffError: String?

    var body: some Scene {
        WindowGroup {
            ContentView()
            .fullScreenCover(item: $dictation) { DictationView(controller: $0) }
            .onOpenURL { url in
                guard let id = KeyboardHandoff.requestID(from: url) else { return }
                if dictation?.id == id { return }
                do {
                    let session = DictationSession(storage: try AppGroupSessionStorage())
                    if dictation == nil, try session.snapshot().state == .failed,
                       try session.snapshot().request?.id == id {
                        // Audio is memory-only. A terminated process cannot restore it.
                        _ = try session.cancel(requestID: id)
                        handoffError = "The saved audio is no longer available. Return to your keyboard and try again."
                        return
                    }
                    guard dictation == nil,
                          try session.snapshot().request?.id == id,
                          try session.snapshot().state == .requested else {
                        handoffError = "The request is no longer available. Return to your keyboard and try again."
                        return
                    }
                    dictation = DictationController(id: id, shared: session)
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
