import Foundation

public struct LastResult: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let expiresAt: Date
}

extension DictationSession {
    /// The single shared slot retains text for 15 minutes after publication.
    /// Copy reads this value without acknowledgement. Insert and Discard acknowledge it.
    public func lastResult() throws -> LastResult? {
        let slot = try snapshot()
        guard slot.state == .ready, let id = slot.request?.id,
              let text = slot.text, let expiry = slot.expiresAt else { return nil }
        return LastResult(id: id, text: text, expiresAt: expiry)
    }

    /// Identity protects a newer result from an old confirmation dialog.
    @discardableResult
    public func discardResult(id: UUID) throws -> Bool {
        try acknowledge(requestID: id)
    }
}
