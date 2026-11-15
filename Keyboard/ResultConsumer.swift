import HandyKit
import UIKit

@MainActor
final class ResultConsumer {
    private let delivery = ResultDelivery()
    private let chip = UIStackView()
    private var visibilityChanged: ((Bool) -> Void)?
    private let preview = UILabel()
    private let insertButton = UIButton(type: .system)
    private var hiddenID: UUID?
    private var insertAction: (() -> Void)?
    private var pendingID: UUID?

    func install(leading: UIView, trailing: UIView, visibilityChanged: @escaping (Bool) -> Void) {
        self.visibilityChanged = visibilityChanged
        var configuration = UIButton.Configuration.borderedProminent()
        configuration.title = "Insert"
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
        configuration.titleLineBreakMode = .byClipping
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 13, weight: .semibold)
            return attributes
        }
        insertButton.configuration = configuration
        insertButton.titleLabel?.numberOfLines = 1
        insertButton.addAction(UIAction { [weak self] _ in self?.insertAction?() }, for: .touchUpInside)
        let dismiss = UIButton(type: .system)
        dismiss.setImage(UIImage(systemName: "xmark"), for: .normal)
        dismiss.accessibilityLabel = "Hide dictation"
        dismiss.backgroundColor = .tertiarySystemFill
        dismiss.layer.cornerRadius = 14
        dismiss.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            hiddenID = pendingID
            hide()
        }, for: .touchUpInside)
        preview.font = .preferredFont(forTextStyle: .caption1)
        preview.adjustsFontForContentSizeCategory = true
        preview.maximumContentSizeCategory = .large
        preview.numberOfLines = 2
        preview.lineBreakMode = .byTruncatingTail
        preview.backgroundColor = .secondarySystemBackground
        preview.layer.cornerRadius = 8
        preview.clipsToBounds = true
        preview.accessibilityIdentifier = "dictation-chip"
        chip.addArrangedSubview(insertButton)
        chip.addArrangedSubview(dismiss)
        chip.spacing = 8
        for item in [preview, chip] { item.translatesAutoresizingMaskIntoConstraints = false }
        leading.addSubview(preview)
        trailing.addSubview(chip)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leading.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: leading.trailingAnchor),
            preview.centerYAnchor.constraint(equalTo: leading.centerYAnchor),
            preview.heightAnchor.constraint(lessThanOrEqualToConstant: 44),
            chip.trailingAnchor.constraint(equalTo: trailing.trailingAnchor),
            chip.leadingAnchor.constraint(greaterThanOrEqualTo: trailing.leadingAnchor),
            chip.centerYAnchor.constraint(equalTo: trailing.centerYAnchor),
            chip.heightAnchor.constraint(equalToConstant: 28),
            insertButton.widthAnchor.constraint(equalToConstant: 64),
            dismiss.widthAnchor.constraint(equalToConstant: 28)
        ])
        hide()
    }

    func hide() { setVisible(false) }

    private func setVisible(_ visible: Bool) {
        chip.isHidden = !visible
        preview.isHidden = !visible
        visibilityChanged?(visible)
    }

    private func showPreview(_ text: String) {
        let changed = preview.accessibilityLabel != text || preview.isHidden
        preview.text = "\u{201C}" + String(text.prefix(14)) + (text.count > 14 ? "…" : "") + "\u{201D}"
        preview.accessibilityLabel = text
        insertButton.accessibilityLabel = "Insert dictation"
        if changed { UIAccessibility.post(notification: .announcement, argument: "Dictation ready. " + text) }
    }

    #if DEBUG
    func showSnapshot(text: String) {
        showPreview(text)
        setVisible(true)
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
            hide()
            return false
        }
        if try delivery.insert(session: session, focus: focus(proxy), insert: { proxy.insertText($0) }) {
            hide()
            return true
        }
        pendingID = id
        if hiddenID != id { showPreview(text) }
        setVisible(hiddenID != id)
        insertAction = { [weak self] in
            guard let self else { return }
            do {
                guard try session.snapshot().request?.id == id else { hide(); return }
                if try delivery.insert(session: session, focus: focus(proxy), explicit: true,
                                       insert: { proxy.insertText($0) }) {
                    hide()
                    inserted()
                }
            } catch { /* Keep the chip available for an acknowledgement retry. */ }
        }
        return false
    }
}
