import HandyKit
import UIKit

/// The controller owns the flow so audio survives cover updates after background expiry.
typealias DictationCoordinator = TranscriptionFlow

@MainActor
final class AppTranscriptionBackgroundTask: TranscriptionBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin(expiration: @escaping @MainActor @Sendable () -> Void) -> Bool {
        guard identifier == .invalid else { return true }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Local dictation") {
            // UIKit calls the expiration handler on the main thread.
            MainActor.assumeIsolated { expiration() }
        }
        return identifier != .invalid
    }

    func end() {
        guard identifier != .invalid else { return }
        let task = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }
}
