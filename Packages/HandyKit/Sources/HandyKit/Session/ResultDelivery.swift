import Foundation

/// Document identity and context must both match. Unknown context always requires a tap.
public struct DeliveryFocus: Equatable {
    public let document: UUID
    public let before: String?
    public let after: String?
    public init(document: UUID, before: String?, after: String?) {
        self.document = document
        self.before = before
        self.after = after
    }
    public var known: Bool { before != nil && after != nil }
}

public final class ResultDelivery {
    private var liveID: UUID?
    private var focus: DeliveryFocus?
    private var inserted = Set<UUID>()
    private let token = UUID()
    public init() {}
    public func begin(requestID: UUID, focus: DeliveryFocus) {
        liveID = requestID
        self.focus = focus
    }
    public func canInsertAutomatically(_ snapshot: DictationSnapshot, focus: DeliveryFocus) -> Bool {
        snapshot.request?.id == liveID && focus.known && self.focus == focus && snapshot.deliveryClaim == nil
    }
    @discardableResult
    public func insert(session: DictationSession, focus: DeliveryFocus, explicit: Bool = false,
                       insert: (String) -> Void) throws -> Bool {
        let snapshot = try session.snapshot()
        guard snapshot.state == .ready, let id = snapshot.request?.id, let text = snapshot.text else { return false }
        if inserted.contains(id) { return try session.acknowledge(requestID: id) }
        guard explicit || canInsertAutomatically(snapshot, focus: focus),
              try session.claimDelivery(requestID: id, token: token, explicit: explicit) else { return false }
        let prefix = focus.before?.unicodeScalars.last.map {
            CharacterSet.letters.union(.punctuationCharacters).contains($0) ? " " : ""
        } ?? ""
        inserted.insert(id)
        insert(prefix + text)
        return try session.acknowledge(requestID: id)
    }
}
