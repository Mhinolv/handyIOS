import HandyKit
import SwiftUI

@main
struct HandyIOSApp: App {
    @State private var handoff = HandoffModel()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let state = SnapshotState.requested {
                SnapshotHost(state: state)
            } else {
                liveContent
            }
            #else
            liveContent
            #endif
        }
    }

    private var liveContent: some View {
        ContentView()
            .handoffPresenter(inSheet: false)
            .modifier(AppPresenceWriter())
            .environment(handoff)
            .onOpenURL { handoff.handle($0) }
    }
}
