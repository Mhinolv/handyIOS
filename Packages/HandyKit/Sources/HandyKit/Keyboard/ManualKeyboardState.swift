/// One capital letter per shift activation. Space and return leave shift unchanged.
public struct ManualShiftState: Sendable {
    public private(set) var isActive = false
    public init() {}
    public mutating func toggle() { isActive.toggle() }
    public func label(for letter: String) -> String {
        isActive ? letter.uppercased() : letter.lowercased()
    }
    public mutating func type(_ letter: String) -> String {
        let text = label(for: letter)
        isActive = false
        return text
    }
}

/// The caller supplies monotonic elapsed time. Late ticks never cause a deletion burst.
public struct DeleteRepeatState: Sendable {
    private var deadline: Duration?
    public init() {}
    public mutating func press(at now: Duration) -> Bool {
        deadline = now + .milliseconds(400)
        return true
    }
    public func delay(at now: Duration) -> Duration? {
        deadline.map { max(.zero, $0 - now) }
    }
    public mutating func tick(at now: Duration) -> Bool {
        guard let deadline, now >= deadline else { return false }
        self.deadline = now + .milliseconds(80)
        return true
    }
    public mutating func release() { deadline = nil }
}

public enum KeyboardAccessStatus {
    /// Nil preserves the current request message and progress indicator.
    public static func message(fullAccess: Bool, manual: Bool, requestPending: Bool) -> String? {
        if !fullAccess {
            return manual ? "Turn on Full Access in Settings to dictate."
                : "Turn on Full Access in Settings to dictate. Use ABC to type."
        }
        return requestPending ? nil : "Tap the mic to dictate"
    }
}
