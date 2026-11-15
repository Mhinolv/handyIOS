import Foundation

/// What a mic tap does for the current shared slot.
public enum KeyboardTapAction: Equatable, Sendable {
    case stop(UUID), consumeResult, open(UUID), newRequest
}

public enum KeyboardTapRule {
    public static func action(for snapshot: DictationSnapshot) -> KeyboardTapAction {
        if snapshot.state == .recording, let id = snapshot.request?.id { return .stop(id) }
        if snapshot.state == .ready { return .consumeResult }
        if let id = snapshot.request?.id { return .open(id) }
        return .newRequest
    }
}

/// Status text for a pending request. Nil keeps the current status.
public enum KeyboardRequestStatus {
    public static let openHandy = "Open Handy, then come back."

    /// #38: when Handy is the host app, the URL opens Handy in place. Do not ask to open it.
    public static func afterOpen(appInFront: Bool) -> String? {
        appInFront ? nil : openHandy
    }

    /// The poll shows recording and transcription status. Only a request that waits for the app asks.
    public static func resumed(state: DictationState, appInFront: Bool) -> String? {
        state == .requested && !appInFront ? openHandy : nil
    }
}

/// The app writes a timestamp to the App Group while it is in front.
/// The keyboard uses it to know that Handy is the host app.
public enum AppPresence {
    public static let key = "appActiveAt"
    public static let lifetime: TimeInterval = 4

    public static func isInFront(activeAt: Date?, now: Date) -> Bool {
        guard let activeAt else { return false }
        return now.timeIntervalSince(activeAt) < lifetime
    }
}

public extension AppPresence {
    static func markActive(_ defaults: UserDefaults?, now: Date = Date()) {
        defaults?.set(now.timeIntervalSince1970, forKey: key)
    }

    static func clear(_ defaults: UserDefaults?) {
        defaults?.removeObject(forKey: key)
    }

    static func isInFront(_ defaults: UserDefaults?, now: Date = Date()) -> Bool {
        guard let value = defaults?.object(forKey: key) as? Double else { return false }
        return isInFront(activeAt: Date(timeIntervalSince1970: value), now: now)
    }
}
