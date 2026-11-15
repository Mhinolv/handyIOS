import HandyKit
import UIKit

/// One height for the dictation and ABC panels, so the keyboard does not jump on a switch.
enum KeyboardLayout {
    static let height: CGFloat = 290
}

final class KeyboardViewController: UIInputViewController {
    #if DEBUG
    var snapshotName: String?
    #endif
    private var fullAccess: Bool {
        #if DEBUG
        if let snapshotName { return snapshotName != "keyboard-full-access-off" }
        #endif
        return hasFullAccess
    }
    private let launcher: any KeyboardAppLaunching = ResponderChainAppLauncher()
    private let consumer = ResultConsumer()
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
        view.tintColor = .systemBlue
        status.text = "Tap the mic to dictate"
        status.font = .preferredFont(forTextStyle: .footnote)
        status.textColor = .secondaryLabel
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 0
        status.textAlignment = .center

        mic.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        mic.tintColor = .white
        mic.backgroundColor = UIColor.systemBlue
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
        manual.context = { [weak self] in self?.textDocumentProxy.documentContextBeforeInput }
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
        consumer.install(in: stack)
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -16)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardLayout.height)
        height.priority = .defaultHigh
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        #if DEBUG
        if let snapshotName {
            globe.isHidden = false
            manual.update(fullAccess: true, needsGlobe: true)
            switch snapshotName {
            case "keyboard-opening": setStatus("Opening Handy…", opening: true)
            case "keyboard-listening":
                setStatus("Listening in handyIOS. Tap to stop.", symbol: "stop.fill")
                mic.backgroundColor = .systemRed
            case "keyboard-inserted": setStatus("Inserted", symbol: "checkmark")
            case "keyboard-full-access-off":
                setStatus(KeyboardAccessStatus.message(fullAccess: false, manual: false, requestPending: false) ?? "")
            case "keyboard-recovery":
                setStatus("Open handyIOS to finish.", symbol: "exclamationmark.circle")
                mic.backgroundColor = .systemOrange
            case "keyboard-chip":
                setStatus("Tap the mic to dictate")
                consumer.showSnapshot(text: "Meet me at the library at three.")
            case "keyboard-abc", "keyboard-shift", "keyboard-caps", "keyboard-numbers", "keyboard-symbols", "keyboard-search":
                dictationPanel.isHidden = true
                manual.isHidden = false
                manual.showSnapshot(snapshotName)
            default: setStatus("Tap the mic to dictate")
            }
            if snapshotName != "keyboard-full-access-off" && snapshotName != "keyboard-opening" {
                mic.setImage(UIImage(systemName: snapshotName == "keyboard-listening" ? "stop.fill" : snapshotName == "keyboard-inserted" ? "checkmark" : snapshotName == "keyboard-recovery" ? "exclamationmark.circle" : "mic.fill"), for: .normal)
            }
            return
        }
        #endif
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

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        manual.update(fullAccess: fullAccess, needsGlobe: needsInputModeSwitchKey,
                      returnType: textDocumentProxy.returnKeyType ?? .default,
                      capitalization: textDocumentProxy.autocapitalizationType ?? .none)
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
        guard fullAccess else {
            setStatus("Turn on Full Access in Settings to dictate. Use ABC to type.")
            return
        }
        resetTask?.cancel()
        do {
            if session == nil { session = DictationSession(storage: try AppGroupSessionStorage()) }
            guard let session else { return }
            let snapshot = try session.snapshot()
            if let message = try session.checkLiveness() {
                requestID = nil
                setStatus(message)
                return
            }
            if snapshot.state == .recording, let id = snapshot.request?.id {
                _ = try session.requestStop(requestID: id)
                return
            }
            if snapshot.state == .ready { consumeResult(); return }
            // Only a new request establishes an automatic insertion target.
            let request = try snapshot.request ?? session.request()
            if snapshot.request == nil { consumer.begin(id: request.id, proxy: textDocumentProxy) }
            requestID = request.id
            setStatus("Opening Handy…", opening: true)
            launcher.open(KeyboardHandoff.url(requestID: request.id), from: self) { [weak self] _ in
                guard self?.requestID == request.id else { return }
                // URL success does not imply an automatic return to the host.
                self?.setStatus("Open Handy, then come back.")
            }
        } catch {
            setStatus("Could not share the request. Enable Allow Full Access, then try again.")
        }
    }

    private func consumeResult() {
        guard fullAccess else { return }
        do {
            if session == nil { session = DictationSession(storage: try AppGroupSessionStorage()) }
            guard let session else { return }
            if let message = try session.checkLiveness() {
                requestID = nil
                setStatus(message)
                return
            }
            let snapshot = try session.snapshot()
            if requestID == nil { requestID = snapshot.request?.id }
            guard let id = requestID else { return }
            if try consumer.consume(session: session, proxy: textDocumentProxy, inserted: { [weak self] in self?.showInserted() }) {
                showInserted()
            } else if snapshot.state == .idle {
                requestID = nil
                setStatus("Tap the mic to dictate")
            } else if snapshot.state == .recording {
                setStatus("Listening in handyIOS. Tap to stop.", symbol: "stop.fill")
                mic.backgroundColor = .systemRed
            } else if snapshot.state == .transcribing {
                setStatus(snapshot.stopMessage.map { $0 + " Transcribing…" } ?? "Transcribing…", opening: true)
            } else if snapshot.state == .failed {
                if snapshot.recoveryAvailable == true {
                    setStatus("Open handyIOS to finish.", symbol: "exclamationmark.circle")
                    mic.backgroundColor = .systemOrange
                } else {
                    _ = try session.cancel(requestID: id)
                    requestID = nil
                    setStatus(snapshot.stopMessage ?? "Request failed. Tap the mic to try again.")
                }
            }
        } catch {
            setStatus("Could not read the shared request. Try again.")
        }
    }

    private func showInserted() {
        requestID = nil
        setStatus("Inserted", symbol: "checkmark")
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            self?.setStatus("Tap the mic to dictate")
        }
    }

    private func setStatus(_ text: String, opening: Bool = false, symbol: String = "mic.fill") {
        let changed = status.text != text
        status.text = text
        mic.backgroundColor = UIColor.systemBlue
        mic.setImage(opening ? nil : UIImage(systemName: fullAccess ? symbol : "mic.slash"), for: .normal)
        mic.accessibilityLabel = fullAccess ? "Dictate" : "Dictation requires Full Access"
        mic.accessibilityHint = fullAccess ? "" : "Turn on Full Access in Settings to dictate."
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
        manual.update(fullAccess: fullAccess, needsGlobe: needsInputModeSwitchKey,
                      returnType: textDocumentProxy.returnKeyType ?? .default,
                      capitalization: textDocumentProxy.autocapitalizationType ?? .none)
        if fullAccess {
            UserDefaults(suiteName: HandyConfiguration.appGroupIdentifier)?.set(true, forKey: HandyConfiguration.keyboardSeenWithFullAccessKey)
        } else {
            session = nil
        }
        // Restore the pending identity before deciding whether to replace the message.
        // This also covers a new extension instance that resumes an existing request.
        var pending = requestID != nil
        if fullAccess {
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
            fullAccess: fullAccess, manual: !manual.isHidden, requestPending: pending
        ) {
            setStatus(message)
        }
    }

    @objc private func space() { textDocumentProxy.insertText(" ") }
    @objc private func deleteText() { textDocumentProxy.deleteBackward() }
    @objc private func returnText() { textDocumentProxy.insertText("\n") }
}
