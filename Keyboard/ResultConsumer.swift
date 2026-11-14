import HandyKit
import UIKit

@MainActor
final class ResultConsumer {
    private let delivery = ResultDelivery()
    private let chip = UIStackView()
    private let preview = UILabel()
    private let insertButton = UIButton(type: .system)
    private var hiddenID: UUID?
    private var insertAction: (() -> Void)?
    private var pendingID: UUID?

    func install(in stack: UIStackView) {
        let insert = insertButton
        insert.configuration = .borderedProminent()
        insert.setTitle("Insert", for: .normal)
        insert.addAction(UIAction { [weak self] _ in self?.insertAction?() }, for: .touchUpInside)
        let hide = UIButton(type: .system)
        hide.setImage(UIImage(systemName: "xmark"), for: .normal)
        hide.accessibilityLabel = "Hide dictation"
        hide.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            hiddenID = pendingID
            chip.isHidden = true
        }, for: .touchUpInside)
        preview.font = .preferredFont(forTextStyle: .footnote)
        chip.addArrangedSubview(preview)
        chip.addArrangedSubview(insert)
        chip.addArrangedSubview(hide)
        chip.spacing = 8
        chip.layer.cornerRadius = 20
        chip.backgroundColor = .secondarySystemBackground
        chip.isHidden = true
        stack.insertArrangedSubview(chip, at: 1)
    }

    #if DEBUG
    func showSnapshot(text: String) {
        preview.text = String(text.prefix(30)) + "…"
        chip.isHidden = false
    }
    #endif

    private func focus(_ proxy: any UITextDocumentProxy) -> DeliveryFocus {
        DeliveryFocus(document: proxy.documentIdentifier, before: proxy.documentContextBeforeInput,
                      after: proxy.documentContextAfterInput)
    }
    func begin(id: UUID, proxy: any UITextDocumentProxy) {
        delivery.begin(requestID: id, focus: focus(proxy))
    }
    func consume(session: DictationSession, proxy: any UITextDocumentProxy,
                 inserted: @escaping () -> Void) throws -> Bool {
        let snapshot = try session.snapshot()
        guard snapshot.state == .ready, let id = snapshot.request?.id, let text = snapshot.text else {
            chip.isHidden = true
            return false
        }
        if try delivery.insert(session: session, focus: focus(proxy), insert: { proxy.insertText($0) }) {
            chip.isHidden = true
            return true
        }
        pendingID = id
        preview.text = String(text.prefix(30)) + (text.count > 30 ? "…" : "")
        insertButton.accessibilityLabel = "Insert dictation: \(text.prefix(30))"
        chip.isHidden = hiddenID == id
        insertAction = { [weak self] in
            guard let self else { return }
            do {
                guard try session.snapshot().request?.id == id else { chip.isHidden = true; return }
                if try delivery.insert(session: session, focus: focus(proxy), explicit: true,
                                       insert: { proxy.insertText($0) }) {
                    chip.isHidden = true
                    inserted()
                }
            } catch { /* Keep the chip available for an acknowledgement retry. */ }
        }
        return false
    }
}
