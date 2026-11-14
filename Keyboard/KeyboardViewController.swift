import HandyKit
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let launcher: any KeyboardAppLaunching = ResponderChainAppLauncher()
    private let consumer = KeyboardResultConsumer()
    private var session: DictationSession?
    private var requestID: UUID?
    private var pollTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private let status = UILabel()
    private let mic = UIButton(type: .system)
    private let globe = UIButton(type: .system)
    private let manual = ManualKeyboardView()
    private var dictationPanel: UIStackView!
    private let progress = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        status.text = "Tap the mic to dictate"
        status.font = .preferredFont(forTextStyle: .footnote)
        status.textColor = .secondaryLabel
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0
        status.textAlignment = .center

        mic.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        mic.tintColor = .white
        mic.backgroundColor = view.tintColor
        mic.layer.cornerRadius = 36
        mic.accessibilityLabel = "Dictate"
        mic.addTarget(self, action: #selector(dictate), for: .touchUpInside)
        progress.translatesAutoresizingMaskIntoConstraints = false
        mic.addSubview(progress)
        NSLayoutConstraint.activate([
            mic.widthAnchor.constraint(equalToConstant: 72),
            mic.heightAnchor.constraint(equalToConstant: 72),
            progress.centerXAnchor.constraint(equalTo: mic.centerXAnchor),
            progress.centerYAnchor.constraint(equalTo: mic.centerYAnchor)
        ])
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.accessibilityLabel = "Next Keyboard"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let row = UIStackView(arrangedSubviews: [
            globe, key("ABC", action: #selector(showManual)), key("space", action: #selector(space)),
            key("⌫", action: #selector(deleteText)), key("return", action: #selector(returnText))
        ])
        row.distribution = .fillEqually
        row.spacing = 8
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let micRow = UIStackView(arrangedSubviews: [UIView(), mic, UIView()])
        micRow.arrangedSubviews[0].widthAnchor.constraint(equalTo: micRow.arrangedSubviews[2].widthAnchor).isActive = true
        dictationPanel = UIStackView(arrangedSubviews: [micRow, row])
        dictationPanel.axis = .vertical
        dictationPanel.spacing = 16
        manual.isHidden = true
        manual.insert = { [weak self] in self?.textDocumentProxy.insertText($0) }
        manual.delete = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        manual.showDictation = { [weak self] in
            self?.manual.stopRepeating()
            self?.manual.isHidden = true
            self?.dictationPanel.isHidden = false
            self?.refreshAccess()
        }
        manual.globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let stack = UIStackView(arrangedSubviews: [status, dictationPanel, manual])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        globe.isHidden = !needsInputModeSwitchKey
        refreshAccess()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.consumeResult()
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pollTask?.cancel()
        pollTask = nil
        resetTask?.cancel()
        manual.stopRepeating()
    }

    private func key(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = title == "⌫" ? "Delete" : title == "ABC" ? "Letters" : title.capitalized
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }

    @objc private func dictate() {
        guard hasFullAccess else {
            setStatus("Turn on Full Access in Settings to dictate. Use ABC to type.")
            return
        }
        resetTask?.cancel()
        do {
            if session == nil { session = DictationSession(storage: try AppGroupSessionStorage()) }
            guard let session else { return }
            let snapshot = try session.snapshot()
            // Resume a pending request, including after the extension was recreated.
            let request = try snapshot.request ?? session.request()
            requestID = request.id
            setStatus("Opening Handy…", opening: true)
            launcher.open(KeyboardHandoff.url(requestID: request.id), from: self) { [weak self] _ in
                // URL success does not imply an automatic return to the host.
                self?.setStatus("Open Handy, then come back.")
            }
        } catch {
            setStatus("Could not share the request. Enable Allow Full Access, then try again.")
        }
    }

    private func consumeResult() {
        guard hasFullAccess else { return }
        do {
            if session == nil { session = DictationSession(storage: try AppGroupSessionStorage()) }
            guard let session else { return }
            let snapshot = try session.snapshot()
            if requestID == nil { requestID = snapshot.request?.id }
            guard let id = requestID else { return }
            if try consumer.consume(session: session, requestID: id, insert: { textDocumentProxy.insertText($0) }) {
                requestID = nil
                setStatus("Inserted", symbol: "checkmark")
                resetTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
                    self?.setStatus("Tap the mic to dictate")
                }
            } else if snapshot.state == .idle {
                requestID = nil
                setStatus("Tap the mic to dictate")
            } else if snapshot.state == .failed {
                _ = try session.cancel(requestID: id)
                requestID = nil
                setStatus("Request failed. Tap the mic to try again.")
            }
        } catch {
            setStatus("Could not read the shared request. Try again.")
        }
    }

    private func setStatus(_ text: String, opening: Bool = false, symbol: String = "mic.fill") {
        let changed = status.text != text
        status.text = text
        mic.setImage(opening ? nil : UIImage(systemName: hasFullAccess ? symbol : "mic.slash"), for: .normal)
        mic.accessibilityLabel = hasFullAccess ? "Dictate" : "Dictation requires Full Access"
        mic.accessibilityHint = hasFullAccess ? "" : "Turn on Full Access in Settings to dictate."
        mic.isEnabled = !opening
        if opening { progress.startAnimating() } else { progress.stopAnimating() }
        if changed { UIAccessibility.post(notification: .announcement, argument: text) }
    }

    @objc private func showManual() {
        dictationPanel.isHidden = true
        manual.isHidden = false
        refreshAccess()
    }

    private func refreshAccess() {
        manual.update(fullAccess: hasFullAccess, needsGlobe: needsInputModeSwitchKey)
        if hasFullAccess {
            UserDefaults(suiteName: HandyConfiguration.appGroupIdentifier)?.set(true, forKey: HandyConfiguration.keyboardSeenWithFullAccessKey)
        } else {
            session = nil
        }
        // Restore the pending identity before deciding whether to replace the message.
        // This also covers a new extension instance that resumes an existing request.
        var pending = requestID != nil
        if hasFullAccess {
            do {
                if session == nil { session = DictationSession(storage: try AppGroupSessionStorage()) }
                if let request = try session?.snapshot().request {
                    if requestID == nil { setStatus("Open Handy, then come back.") }
                    requestID = request.id
                    pending = true
                }
            } catch {
                setStatus("Could not read the shared request. Try again.")
                return
            }
        }
        if let message = KeyboardAccessStatus.message(
            fullAccess: hasFullAccess, manual: !manual.isHidden, requestPending: pending
        ) {
            setStatus(message)
        }
    }

    @objc private func space() { textDocumentProxy.insertText(" ") }
    @objc private func deleteText() { textDocumentProxy.deleteBackward() }
    @objc private func returnText() { textDocumentProxy.insertText("\n") }
}
