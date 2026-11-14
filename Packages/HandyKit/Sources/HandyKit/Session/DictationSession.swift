import Foundation

public protocol SessionClock {
    var now: Date { get }
}

public struct SystemSessionClock: SessionClock {
    public init() {}
    public var now: Date { Date() }
}

/// The store must hold one exclusive, cross-process lock for the entire transaction.
/// If the closure throws, the store must preserve the previous data.
public protocol SessionStorage {
    func transaction<T>(_ body: (inout Data?) throws -> T) throws -> T
}

public enum DictationState: String, Codable, Sendable {
    case idle, requested, recording, transcribing, ready, failed
}

public struct DictationRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
}

public struct DictationSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public fileprivate(set) var request: DictationRequest?
    public fileprivate(set) var state: DictationState
    public fileprivate(set) var text: String?
    public fileprivate(set) var expiresAt: Date?
    /// The app observes this flag and stops capture. Only the live request can set it.
    public fileprivate(set) var stopRequested: Bool

    fileprivate static let idle = DictationSnapshot(
        version: 1, request: nil, state: .idle, text: nil,
        expiresAt: nil, stopRequested: false
    )
}

public enum DictationProtocolError: Error, Equatable {
    case busy, unsupportedVersion(Int)
}

/// One session occupies the slot until acknowledgement, cancellation, or expiry.
/// Consumers must acknowledge only after text insertion. An acknowledgement clears text.
/// Delivery is at least once until acknowledgement, not an atomic text-editor transaction.
/// Every operation clears expired data before it reads or changes the slot. Clients must
/// poll snapshot while active and on resume. No background timer runs in this library.
/// Capture has three minutes from startRecording. A short grace period permits completion after timer delay.
/// startTranscription must follow capture and gives transcription a separate two-minute window.
/// The app must stop capture at its deadline. The protocol does not control the microphone.
public final class DictationSession {
    public static let maximumDictationDuration: TimeInterval = 180
    public static let captureStopMargin: TimeInterval = 1
    public static let captureCompletionGrace: TimeInterval = 2
    public static let maximumTranscriptionDuration: TimeInterval = 120
    public static let unclaimedResultLifetime: TimeInterval = 900

    private let storage: any SessionStorage
    private let clock: any SessionClock

    public init(storage: any SessionStorage, clock: any SessionClock = SystemSessionClock()) {
        self.storage = storage
        self.clock = clock
    }

    public func snapshot() throws -> DictationSnapshot {
        try update { $0 }
    }

    @discardableResult
    public func request() throws -> DictationRequest {
        // Return busy after the transaction, so expiry cleanup can still commit.
        let result: DictationRequest? = try update { slot in
            guard slot.state == .idle else { return nil }
            let request = DictationRequest(id: UUID(), createdAt: clock.now)
            slot.request = request
            slot.state = .requested
            slot.expiresAt = clock.now.addingTimeInterval(Self.maximumDictationDuration)
            return request
        }
        guard let result else { throw DictationProtocolError.busy }
        return result
    }

    @discardableResult
    public func startRecording(requestID: UUID) throws -> Bool {
        try transition(requestID, from: .requested, to: .recording)
    }

    @discardableResult
    public func startTranscription(requestID: UUID) throws -> Bool {
        try transition(requestID, from: .recording, to: .transcribing)
    }

    /// Only the app that owns bounded capture may call this after it releases the microphone.
    /// Timer delivery can follow the deadline. Preserve captured audio without reviving a replaced request.
    @discardableResult
    public func finishCapture(requestID: UUID) throws -> Bool {
        try transition(requestID, from: .recording, to: .transcribing)
    }

    @discardableResult
    public func requestStop(requestID: UUID) throws -> Bool {
        try update { slot in
            guard slot.request?.id == requestID,
                  slot.state == .requested || slot.state == .recording else { return false }
            slot.stopRequested = true
            return true
        }
    }

    @discardableResult
    public func publish(text: String, requestID: UUID) throws -> Bool {
        try update { slot in
            guard slot.request?.id == requestID, slot.state == .transcribing else { return false }
            slot.text = text
            slot.state = .ready
            slot.expiresAt = clock.now.addingTimeInterval(Self.unclaimedResultLifetime)
            return true
        }
    }

    @discardableResult
    public func acknowledge(requestID: UUID) throws -> Bool {
        try update { slot in
            guard slot.request?.id == requestID, slot.state == .ready else { return false }
            slot = .idle
            return true
        }
    }

    @discardableResult
    public func cancel(requestID: UUID) throws -> Bool {
        try update { slot in
            guard slot.request?.id == requestID else { return false }
            slot = .idle
            return true
        }
    }

    @discardableResult
    public func fail(requestID: UUID) throws -> Bool {
        try update { slot in
            guard slot.request?.id == requestID,
                  [.requested, .recording, .transcribing].contains(slot.state) else { return false }
            slot.state = .failed
            return true
        }
    }

    private func transition(_ id: UUID, from: DictationState, to: DictationState) throws -> Bool {
        try update { slot in
            guard slot.request?.id == id, slot.state == from else { return false }
            slot.state = to
            let duration = to == .recording
                ? Self.maximumDictationDuration : Self.maximumTranscriptionDuration
            slot.expiresAt = clock.now.addingTimeInterval(duration)
            return true
        }
    }

    private func update<T>(_ body: (inout DictationSnapshot) throws -> T) throws -> T {
        try storage.transaction { data in
            var slot = try data.map { try JSONDecoder().decode(DictationSnapshot.self, from: $0) } ?? .idle
            guard slot.version == 1 else { throw DictationProtocolError.unsupportedVersion(slot.version) }
            if let expiry = slot.expiresAt {
                // Keyboard polls must preserve the slot while the app releases capture.
                let expired = slot.state == .recording
                    ? clock.now > expiry.addingTimeInterval(Self.captureCompletionGrace)
                    : clock.now >= expiry
                if expired { slot = .idle }
            }
            let result = try body(&slot)
            data = try JSONEncoder().encode(slot)
            return result
        }
    }
}
