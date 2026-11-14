import Foundation

/// The URL carries identity only. Transcript text stays in the App Group.
public enum KeyboardHandoff {
    public static func url(requestID: UUID) -> URL {
        URL(string: "handyios://dictate/\(requestID.uuidString)")!
    }

    public static func requestID(from url: URL) -> UUID? {
        guard url.scheme == "handyios", url.host == "dictate",
              url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// Exercise the protocol without audio or an ASR engine.
    @discardableResult
    public static func publishFakeResult(session: DictationSession, requestID: UUID) throws -> Bool {
        let snapshot = try session.snapshot()
        guard snapshot.request?.id == requestID, snapshot.state == .requested else { return false }
        if snapshot.stopRequested { return try session.cancel(requestID: requestID) }
        guard try session.startRecording(requestID: requestID),
              try session.startTranscription(requestID: requestID) else { return false }
        return try session.publish(text: "handyIOS test text.", requestID: requestID)
    }
}

/// Retain this consumer across keyboard appearances to avoid duplicate insertion after an acknowledgement error.
public final class KeyboardResultConsumer {
    private var insertedID: UUID?
    public init() {}

    @discardableResult
    public func consume(
        session: DictationSession, requestID: UUID, insert: (String) -> Void
    ) throws -> Bool {
        let snapshot = try session.snapshot()
        guard snapshot.request?.id == requestID, snapshot.state == .ready,
              let text = snapshot.text else { return false }
        if insertedID != requestID {
            insert(text)
            insertedID = requestID
        }
        return try session.acknowledge(requestID: requestID)
    }
}
