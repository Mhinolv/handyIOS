import HandyKit
import UIKit

/// All dictation states share one bar above the four key rows.
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
    private let warning = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
    private var statusLeading: NSLayoutConstraint!
    private let mic = UIButton(type: .system)
    private let manual = ManualKeyboardView()
    private let topBar = UIView()
    private let progress = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.tintColor = .systemBlue
        status.text = "Tap the mic to dictate"
        status.font = .preferredFont(forTextStyle: .caption1)
        status.textColor = .secondaryLabel
        status.adjustsFontForContentSizeCategory = true
        status.maximumContentSizeCategory = .large
        status.numberOfLines = 2
        status.lineBreakMode = .byTruncatingTail
        status.accessibilityIdentifier = "dictation-status"
        mic.tintColor = .white
        mic.layer.cornerRadius = 18
        mic.accessibilityIdentifier = "dictation-mic"
        mic.addTarget(self, action: #selector(dictate), for: .touchUpInside)
        progress.color = .white
        for item in [status, mic, progress, topBar] { item.translatesAutoresizingMaskIntoConstraints = false }
        warning.translatesAutoresizingMaskIntoConstraints = false
        warning.tintColor = .label
        warning.isHidden = true
        topBar.addSubview(warning)
        topBar.addSubview(status)
        topBar.addSubview(mic)
        mic.addSubview(progress)
        let leading = UIView()
        let trailing = UIView()
        for zone in [leading, trailing] {
            zone.translatesAutoresizingMaskIntoConstraints = false
            topBar.addSubview(zone)
        }
        consumer.install(leading: leading, trailing: trailing) { [weak self] visible in
            self?.status.isHidden = visible
        }
        statusLeading = status.leadingAnchor.constraint(equalTo: topBar.leadingAnchor)
        NSLayoutConstraint.activate([
            warning.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            warning.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            warning.widthAnchor.constraint(equalToConstant: 12),
            warning.heightAnchor.constraint(equalToConstant: 12),
            topBar.heightAnchor.constraint(equalToConstant: 44),
            mic.widthAnchor.constraint(equalToConstant: 64),
            mic.heightAnchor.constraint(equalToConstant: 36),
            mic.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            mic.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            statusLeading,
            status.trailingAnchor.constraint(equalTo: mic.leadingAnchor, constant: -8),
            status.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            status.heightAnchor.constraint(lessThanOrEqualToConstant: 44),
            leading.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            leading.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            leading.topAnchor.constraint(equalTo: topBar.topAnchor),
            leading.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            trailing.leadingAnchor.constraint(equalTo: mic.trailingAnchor, constant: 8),
            trailing.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            trailing.topAnchor.constraint(equalTo: topBar.topAnchor),
            trailing.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            progress.centerXAnchor.constraint(equalTo: mic.centerXAnchor),
            progress.centerYAnchor.constraint(equalTo: mic.centerYAnchor)
        ])
        manual.context = { [weak self] in self?.textDocumentProxy.documentContextBeforeInput }
        manual.insert = { [weak self] in self?.textDocumentProxy.insertText($0) }
        manual.delete = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        manual.globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let stack = UIStackView(arrangedSubviews: [topBar, manual])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardLayout.height)
        height.priority = .defaultHigh
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        #if DEBUG
        if let snapshotName {
            consumer.hide()
            manual.update(fullAccess: fullAccess, needsGlobe: true)
            setStatus("Tap the mic to dictate")
            switch snapshotName {
            case "keyboard-launch-failed": showLaunchResult(false)
            case "keyboard-transcribing": setStatus("Transcribing…", opening: true)
            case "keyboard-opening": setStatus("Opening Handy…", opening: true)
            case "keyboard-listening":
                setStatus("Listening in Handy. Tap to stop.", symbol: "stop.fill")
                mic.backgroundColor = .systemRed
            case "keyboard-inserted": setStatus("Inserted", symbol: "checkmark")
            case "keyboard-full-access-off":
                setStatus("Turn on Full Access in Settings to dictate.")
            case "keyboard-recovery":
                setStatus("Open Handy to finish.", symbol: "exclamationmark.circle")
                mic.backgroundColor = .systemOrange
            case "keyboard-chip":
                setStatus("Tap the mic to dictate")
                consumer.showSnapshot(text: "Meet me at the library at three.")
            case "keyboard-abc", "keyboard-shift", "keyboard-caps", "keyboard-numbers", "keyboard-symbols", "keyboard-search":
                manual.showSnapshot(snapshotName)
            default: setStatus("Tap the mic to dictate")
            }
            return
        }
        #endif
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
        if requestID == nil { showKeyRows() }
        manual.stopRepeating()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        manual.update(fullAccess: fullAccess, needsGlobe: needsInputModeSwitchKey,
                      returnType: textDocumentProxy.returnKeyType ?? .default,
                      capitalization: textDocumentProxy.autocapitalizationType ?? .none)
    }

    /// #38: Handy writes a timestamp while it is in front. Then the keyboard runs inside Handy.
    private var appInFront: Bool {
        AppPresence.isInFront(UserDefaults(suiteName: HandyConfiguration.appGroupIdentifier))
    }

    @objc private func dictate() {
        guard fullAccess else {
            HandyLog.keyboard.notice("tap refused: no full access")
            setStatus("Turn on Full Access in Settings to dictate.")
            return
        }
        resetTask?.cancel()
        do {
            if session == nil { session = DictationSession(storage: try AppGroupSessionStorage()) }
            guard let session else { return }
            if let message = try session.checkLiveness() {
                HandyLog.keyboard.notice("tap: liveness cleared the slot: \(message, privacy: .public)")
                requestID = nil
                showKeyRows()
                setStatus(message)
                return
            }
            let snapshot = try session.snapshot()
            let request: DictationRequest
            switch KeyboardTapRule.action(for: snapshot) {
            case .stop(let id):
                let sent = try session.requestStop(requestID: id)
                HandyLog.keyboard.notice("tap: stop asked for \(HandyLog.short(id), privacy: .public), accepted \(sent, privacy: .public)")
                return
            case .consumeResult:
                HandyLog.keyboard.notice("tap: result ready, consume")
                consumeResult()
                return
            case .open(let id):
                // Repeated taps reuse the pending request, so the app and the keyboard stay on one id.
                guard let existing = snapshot.request, existing.id == id else { return }
                request = existing
                HandyLog.keyboard.notice("tap: reuse request \(HandyLog.short(id), privacy: .public) state \(snapshot.state.rawValue, privacy: .public)")
            case .newRequest:
                // Only a new request establishes an automatic insertion target.
                request = try session.request()
                consumer.begin(id: request.id, proxy: textDocumentProxy)
                HandyLog.keyboard.notice("tap: new request \(HandyLog.short(request.id), privacy: .public)")
            }
            requestID = request.id
            setStatus("Opening Handy…", opening: true)
            let inFront = appInFront
            HandyLog.keyboard.notice("open url: request \(HandyLog.short(request.id), privacy: .public), Handy in front \(inFront, privacy: .public)")
            launcher.open(KeyboardHandoff.url(requestID: request.id), from: self) { [weak self] success in
                HandyLog.keyboard.notice("open url result: request \(HandyLog.short(request.id), privacy: .public), success \(success, privacy: .public)")
                guard let self, self.requestID == request.id else { return }
                // URL success does not imply an automatic return to the host.
                // Inside Handy, the poll shows the recording status instead.
                self.showLaunchResult(success)
            }
        } catch {
            HandyLog.keyboard.error("tap failed: \(String(describing: error), privacy: .public)")
            setStatus("Could not share the request. Enable Allow Full Access, then try again.")
        }
    }

    private func consumeResult() {
        guard fullAccess else { return }
        do {
            if session == nil { session = DictationSession(storage: try AppGroupSessionStorage()) }
            guard let session else { return }
            if let message = try session.checkLiveness() {
                HandyLog.keyboard.notice("poll: liveness cleared request \(HandyLog.short(self.requestID), privacy: .public): \(message, privacy: .public)")
                requestID = nil
                showKeyRows()
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
                showKeyRows()
                setStatus("Tap the mic to dictate")
            } else if snapshot.state == .recording {
                setStatus("Listening in Handy. Tap to stop.", symbol: "stop.fill")
                mic.backgroundColor = .systemRed
            } else if snapshot.state == .transcribing {
                setStatus(snapshot.stopMessage.map { $0 + " Transcribing…" } ?? "Transcribing…", opening: true)
            } else if snapshot.state == .failed {
                if snapshot.recoveryAvailable == true {
                    setStatus("Open Handy to finish.", symbol: "exclamationmark.circle")
                    mic.backgroundColor = .systemOrange
                } else {
                    HandyLog.keyboard.notice("poll: request \(HandyLog.short(id), privacy: .public) failed, slot cleared")
                    _ = try session.cancel(requestID: id)
                    requestID = nil
                    showKeyRows()
                    setStatus(snapshot.stopMessage ?? "Request failed. Tap the mic to try again.")
                }
            }
        } catch {
            HandyLog.keyboard.error("poll failed: \(String(describing: error), privacy: .public)")
            setStatus("Could not read the shared request. Try again.")
        }
    }

    func showInserted() {
        HandyLog.keyboard.notice("inserted: request \(HandyLog.short(self.requestID), privacy: .public)")
        requestID = nil
        setStatus("Inserted", symbol: "checkmark")
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            self?.showKeyRows()
            self?.setStatus("Tap the mic to dictate")
        }
    }

    // The adapter result is authoritative. A pending request does not prove a successful launch.
    func showLaunchResult(_ success: Bool) {
        if !success {
            setStatus("Handy did not open. Open it, then try again.", symbol: "exclamationmark.triangle")
        } else if let text = KeyboardRequestStatus.afterOpen(appInFront: appInFront) {
            setStatus(text.replacingOccurrences(of: "handyIOS", with: "Handy"))
        }
    }

    private func setStatus(_ text: String, opening: Bool = false, symbol: String = "mic.fill") {
        let text = text.replacingOccurrences(of: "handyIOS", with: "Handy")
        let changed = status.text != text
        status.text = text
        warning.isHidden = symbol != "exclamationmark.triangle"
        statusLeading.constant = warning.isHidden ? 0 : 16
        status.textColor = ["stop.fill", "exclamationmark.triangle"].contains(symbol) ? .label : .secondaryLabel
        mic.backgroundColor = fullAccess ? (symbol == "stop.fill" ? .systemRed : .systemBlue) : .systemGray
        mic.setImage(opening ? nil : UIImage(systemName: fullAccess ? (symbol == "exclamationmark.triangle" ? "mic.fill" : symbol) : "mic.slash"), for: .normal)
        mic.accessibilityLabel = fullAccess ? (symbol == "stop.fill" ? "Stop Dictation" : "Dictate") : "Dictation requires Full Access"
        mic.accessibilityHint = fullAccess ? "" : "Turn on Full Access in Settings to dictate."
        mic.isEnabled = fullAccess && !opening
        if opening { progress.startAnimating() } else { progress.stopAnimating() }
        if changed { UIAccessibility.post(notification: .announcement, argument: text) }
    }

    private func showKeyRows() { manual.isHidden = false }

    private func refreshAccess() {
        manual.update(fullAccess: fullAccess, needsGlobe: needsInputModeSwitchKey,
                      returnType: textDocumentProxy.returnKeyType ?? .default,
                      capitalization: textDocumentProxy.autocapitalizationType ?? .none)
        if fullAccess {
            UserDefaults(suiteName: HandyConfiguration.appGroupIdentifier)?.set(true, forKey: HandyConfiguration.keyboardSeenWithFullAccessKey)
        } else {
            session = nil
            requestID = nil
            showKeyRows()
        }
        // Restore the pending identity before deciding whether to replace the message.
        // This also covers a new extension instance that resumes an existing request.
        var pending = requestID != nil
        if fullAccess {
            do {
                if session == nil { session = DictationSession(storage: try AppGroupSessionStorage()) }
                if let snapshot = try session?.snapshot(), let request = snapshot.request {
                    // #38: never ask to open Handy while it records or while it is the host app.
                    if requestID == nil,
                       let text = KeyboardRequestStatus.resumed(state: snapshot.state, appInFront: appInFront) {
                        setStatus(text)
                    }
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
            setStatus(fullAccess ? message : "Turn on Full Access in Settings to dictate.")
        }
    }

}
