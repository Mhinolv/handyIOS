import Foundation

/// What the app does with an incoming `handyios://dictate/<id>` URL.
public enum HandoffDecision: Equatable, Sendable {
    /// The URL names the request that the current controller already owns.
    case ignoreDuplicate
    /// Make a controller for the request.
    case start
    /// Cancel the stale controller, then make a controller for the request.
    case replace(previous: UUID)
    /// The process restarted after a failure. Memory-only audio is gone.
    case savedAudioLost
    /// The request is not in the shared slot, or it is not in the requested state.
    case unavailable(reason: String)
}

/// The app's current controller, as the router sees it.
public struct HandoffController: Equatable, Sendable {
    public let id: UUID
    public let state: MicrophoneSession.State
    public init(id: UUID, state: MicrophoneSession.State) {
        self.id = id
        self.state = state
    }
}

public enum HandoffRouter {
    public static func decide(
        requestID: UUID, current: HandoffController?, snapshot: DictationSnapshot
    ) -> HandoffDecision {
        let finished: Set<MicrophoneSession.State> = [.cancelled, .failed, .denied]
        if let current, current.id == requestID, !finished.contains(current.state) {
            return .ignoreDuplicate
        }
        if current == nil, snapshot.state == .failed, snapshot.request?.id == requestID {
            return .savedAudioLost
        }
        guard snapshot.request?.id == requestID else { return .unavailable(reason: "request not in slot") }
        guard snapshot.state == .requested else {
            return .unavailable(reason: "slot state \(snapshot.state.rawValue)")
        }
        // #38: a live request that the current controller does not own makes that controller stale.
        // A stale controller blocked every later request, so the keyboard and the app split.
        if let current { return .replace(previous: current.id) }
        return .start
    }
}
