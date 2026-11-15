import HandyKit
import Observation
import SwiftUI

/// #38: owns the dictation handoff, so the top presenter can show it.
/// SwiftUI cannot present the root cover while the setup sheet is open.
@MainActor @Observable
final class HandoffModel {
    var dictation: DictationController?
    var error: String?
    /// True while a sheet with a text field is open. That sheet then presents dictation.
    var sheetOpen = false

    func handle(_ url: URL) {
        guard let id = KeyboardHandoff.requestID(from: url) else {
            HandyLog.session.notice("url ignored: not a dictation url")
            return
        }
        HandyLog.session.notice("url received: request \(HandyLog.short(id), privacy: .public), sheetOpen \(self.sheetOpen, privacy: .public)")
        do {
            let session = DictationSession(storage: try AppGroupSessionStorage())
            let snapshot = try session.snapshot()
            let current = dictation.map { HandoffController(id: $0.id, state: $0.state) }
            let decision = HandoffRouter.decide(requestID: id, current: current, snapshot: snapshot)
            switch decision {
            case .ignoreDuplicate:
                HandyLog.session.notice("url ignored: request \(HandyLog.short(id), privacy: .public) already owned")
            case .savedAudioLost:
                // Audio is memory-only. A terminated process cannot restore it.
                _ = try session.cancel(requestID: id)
                HandyLog.session.error("url failed: saved audio lost for \(HandyLog.short(id), privacy: .public)")
                error = "The saved audio is no longer available. Return to your keyboard and try again."
            case .unavailable(let reason):
                HandyLog.session.error("url refused: \(reason, privacy: .public), slot request \(HandyLog.short(snapshot.request?.id), privacy: .public)")
                error = "The request is no longer available. Return to your keyboard and try again."
            case .replace(let previous):
                HandyLog.session.notice("controller replaced: stale \(HandyLog.short(previous), privacy: .public) state \(String(describing: current?.state), privacy: .public)")
                dictation?.cancel(reason: "replaced by a new request")
                dictation = DictationController(id: id, shared: session)
            case .start:
                HandyLog.session.notice("controller created: request \(HandyLog.short(id), privacy: .public)")
                dictation = DictationController(id: id, shared: session)
            }
        } catch {
            HandyLog.session.error("url failed: shared request unreadable: \(String(describing: error), privacy: .public)")
            self.error = "Handy could not read the shared request. Return to your keyboard and try again."
        }
    }
}

/// Attach at the root with `inSheet: false` and in each sheet with a text field with `inSheet: true`.
/// Only the top presenter shows the cover and the alert.
struct HandoffPresenter: ViewModifier {
    let inSheet: Bool
    @Environment(HandoffModel.self) private var model

    private var active: Bool { model.sheetOpen == inSheet }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: Binding(
                get: { active ? model.dictation : nil },
                set: { value in
                    guard value == nil, active, let current = model.dictation else { return }
                    // Every user dismiss ends the controller first. A dismiss of a live controller
                    // comes from a replaced view, so keep the new controller.
                    if [.idle, .askingPermission, .recording].contains(current.state) {
                        HandyLog.session.notice("cover dismiss ignored: request \(HandyLog.short(current.id), privacy: .public) is live")
                        return
                    }
                    HandyLog.session.notice("cover dismissed: request \(HandyLog.short(current.id), privacy: .public)")
                    model.dictation = nil
                }
            )) { DictationView(controller: $0) }
            .alert("Could Not Complete Request", isPresented: Binding(
                get: { active && model.dictation == nil && model.error != nil },
                set: { if !$0 { model.error = nil } }
            )) {
                Button("OK") { model.error = nil }
            } message: {
                Text(model.error ?? "")
            }
    }
}

extension View {
    func handoffPresenter(inSheet: Bool) -> some View { modifier(HandoffPresenter(inSheet: inSheet)) }
}

/// Tells the keyboard that Handy is the host app, so it does not ask the user to open Handy.
struct AppPresenceWriter: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            let defaults = UserDefaults(suiteName: HandyConfiguration.appGroupIdentifier)
            guard scenePhase == .active else {
                AppPresence.clear(defaults)
                return
            }
            while !Task.isCancelled {
                AppPresence.markActive(defaults)
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
