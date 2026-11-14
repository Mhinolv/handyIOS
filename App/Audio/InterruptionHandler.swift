import AVFoundation
import HandyKit

enum InterruptionHandler {
    static func event(_ notification: Notification) -> CaptureRecoveryEvent? {
        if notification.name == AVAudioSession.interruptionNotification {
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
            return type == .began ? .interruptionBegan : .interruptionEnded
        }
        let session = AVAudioSession.sharedInstance()
        // Preserve working routes. Stop only when capture no longer has a usable input.
        return .routeChanged(microphoneAvailable:
            session.isInputAvailable && !session.currentRoute.inputs.isEmpty)
    }
}
