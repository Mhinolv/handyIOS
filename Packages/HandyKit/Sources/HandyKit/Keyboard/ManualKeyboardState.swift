import Foundation

/// Shift uses caller-supplied monotonic time for double taps.
public struct ManualShiftState: Sendable {
    public enum Mode: Sendable { case off, once, locked }
    public private(set) var mode: Mode = .off
    private var lastTap: Duration?
    public var isActive: Bool { mode != .off }
    public init() {}
    public mutating func toggle() { mode = isActive ? .off : .once; lastTap = nil }
    public mutating func tap(at now: Duration) {
        if mode == .locked { mode = .off; lastTap = nil }
        else if let lastTap, now >= lastTap, now - lastTap <= .milliseconds(300) {
            mode = .locked; self.lastTap = nil
        } else { mode = isActive ? .off : .once; lastTap = now }
    }
    public func label(for letter: String) -> String {
        isActive ? letter.uppercased() : letter.lowercased()
    }
    public mutating func type(_ letter: String) -> String {
        let text = label(for: letter)
        if letter.contains(where: { $0.isLetter }) {
            if mode == .once { mode = .off }
            lastTap = nil
        }
        return text
    }
    public mutating func capitalize(_ active: Bool) {
        if mode != .locked { mode = active ? .once : .off }
    }
}

public enum ManualKeyboardLayer: Sendable, CaseIterable {
    case letters, numbers, symbols
    public var rows: [String] {
        switch self {
        case .letters: ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        case .numbers: ["1234567890", "-/:;()$&@\"", ".,?!'"]
        case .symbols: ["[]{}#%^*+=", "_\\|~<>€£¥•", ".,?!'"]
        }
    }
}

public struct ManualKeyboardState: Sendable {
    public private(set) var layer: ManualKeyboardLayer = .letters
    public var shift = ManualShiftState()
    public init() {}
    public mutating func select(_ layer: ManualKeyboardLayer) { self.layer = layer }
    public mutating func type(_ text: String) -> String {
        layer == .letters ? shift.type(text) : text
    }
    public static func sentenceStart(before context: String?) -> Bool {
        guard let context else { return false }
        if context.isEmpty || context.last == "\n" { return true }
        guard context.last?.isWhitespace == true else { return false }
        return context.trimmingCharacters(in: .whitespaces).last.map { ".!?\n".contains($0) } ?? true
    }
    public static func replacesSpace(before context: String?) -> Bool {
        guard let context, context.last == " ", let previous = context.dropLast().last else { return false }
        return previous.isLetter || previous.isNumber
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
