/// Shared recovery copy and fakeable capture events.
public enum DictationRecovery: Equatable, Sendable {
    case interruption, route, expiry, transcription
    public var symbol: String {
        switch self {
        case .interruption: "phone.down.fill"
        case .route: "mic.slash"
        case .expiry: "exclamationmark.arrow.circlepath"
        case .transcription: "exclamationmark.triangle.fill"
        }
    }
    public var title: String {
        switch self {
        case .interruption, .route: "Recording Stopped"
        case .expiry: "Transcription Did Not Finish"
        case .transcription: "Transcription Failed"
        }
    }
    public var body: String {
        switch self {
        case .interruption: "A call or alarm took the microphone. Your speech is saved."
        case .route: "The microphone changed. Your speech is saved."
        case .expiry: "iOS stopped handyIOS in the background."
        case .transcription: "Try again with the same audio."
        }
    }
    public var action: String {
        self == .interruption || self == .route ? "Transcribe" : "Retry"
    }
}

public enum CaptureRecoveryEvent {
    case interruptionBegan, interruptionEnded, routeChanged(microphoneAvailable: Bool)
    public var recovery: DictationRecovery? {
        switch self {
        case .interruptionBegan: .interruption
        case .routeChanged(false): .route
        case .interruptionEnded, .routeChanged(true): nil
        }
    }
}
