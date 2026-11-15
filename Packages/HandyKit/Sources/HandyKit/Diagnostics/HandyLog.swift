import Foundation
import os

/// #38: diagnostics for the device log. Messages are public and carry reasons only.
/// Never log transcript text or audio.
public enum HandyLog {
    public static let subsystem = "com.mhinolv.handyios"
    public static let session = Logger(subsystem: subsystem, category: "session")
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let keyboard = Logger(subsystem: subsystem, category: "keyboard")

    /// The first 8 characters of a request id. Request ids are random and hold no user data.
    public static func short(_ id: UUID?) -> String {
        id.map { String($0.uuidString.prefix(8)) } ?? "none"
    }
}
