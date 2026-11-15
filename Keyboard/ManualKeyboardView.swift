import HandyKit
import UIKit

/// All typing uses the host proxy, without shared storage or Full Access.
@MainActor
final class ManualKeyboardView: UIStackView {
    var insert: (String) -> Void = { _ in }
    var delete: () -> Void = {}
    var context: () -> String? = { nil }
    var showDictation: () -> Void = {}
    let globe = UIButton(type: .system)
    private let mic = UIButton(type: .system)
    private var state = ManualKeyboardState()
    private var returnType: UIReturnKeyType = .default
    private var capitalization: UITextAutocapitalizationType = .none
    private var deleteState = DeleteRepeatState()
    private let clock = ContinuousClock()
    private let clockOrigin = ContinuousClock.now
    private var repeatTask: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 12
        configure(globe, title: "", label: "Next Keyboard", function: true)
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        configure(mic, title: "", label: "Dictation", function: true)
        mic.addAction(UIAction { [weak self] _ in self?.showDictation() }, for: .touchUpInside)
        globe.widthAnchor.constraint(equalToConstant: 44).isActive = true
        mic.widthAnchor.constraint(equalToConstant: 30).isActive = true
        rebuild()
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(fullAccess: Bool, needsGlobe: Bool, returnType: UIReturnKeyType = .default,
                capitalization: UITextAutocapitalizationType = .none) {
        let changed = globe.isHidden != !needsGlobe || self.returnType != returnType
        globe.isHidden = !needsGlobe
        self.returnType = returnType
        self.capitalization = capitalization
        mic.setImage(UIImage(systemName: fullAccess ? "mic.fill" : "mic.slash"), for: .normal)
        mic.accessibilityLabel = fullAccess ? "Dictation" : "Dictation requires Full Access"
        refreshContext(force: changed)
    }

    func refreshContext(force: Bool = false) {
        guard repeatTask == nil else { return }
        let oldMode = state.shift.mode
        if capitalization == .sentences {
            state.shift.capitalize(ManualKeyboardState.sentenceStart(before: context()))
        } else if capitalization == .allCharacters { state.shift.capitalize(true) }
        else if capitalization == .words {
            state.shift.capitalize(context()?.last?.isWhitespace ?? true)
        }
        if force || oldMode != state.shift.mode { rebuild() }
    }

    #if DEBUG
    func showSnapshot(_ name: String) {
        if name == "keyboard-numbers" { state.select(.numbers) }
        if name == "keyboard-symbols" { state.select(.symbols) }
        if name == "keyboard-shift" || name == "keyboard-caps" { state.shift.tap(at: .zero) }
        if name == "keyboard-caps" { state.shift.tap(at: .milliseconds(100)) }
        if name == "keyboard-search" { returnType = .search }
        rebuild()
    }
    #endif

    private func type(_ value: String) {
        if value == " ", ManualKeyboardState.replacesSpace(before: context()) {
            delete(); insert(". ")
        } else { insert(state.type(value)) }
        // Proxy context can update after this callback. Refresh once the host receives the edit.
        rebuild()
    }

    private func select(_ layer: ManualKeyboardLayer) { state.select(layer); rebuild() }

    private func rebuild() {
        stopRepeating()
        for view in arrangedSubviews { removeArrangedSubview(view); view.removeFromSuperview() }
        for (index, characters) in state.layer.rows.enumerated() {
            let row = UIStackView()
            row.spacing = 6
            row.distribution = .fillEqually
            row.heightAnchor.constraint(equalToConstant: 42).isActive = true
            if index == 2 {
                if state.layer == .letters {
                    let shift = button("", label: state.shift.mode == .locked ? "Caps Lock" : "Shift", function: true) { [weak self] in
                        guard let self else { return }
                        self.state.shift.tap(at: self.elapsed); self.rebuild()
                    }
                    shift.setImage(UIImage(systemName: state.shift.mode == .locked ? "capslock.fill" : state.shift.isActive ? "shift.fill" : "shift"), for: .normal)
                    shift.accessibilityValue = state.shift.isActive ? "On" : "Off"
                    if state.shift.isActive { shift.backgroundColor = characterFill }
                    row.addArrangedSubview(shift)
                } else {
                    row.addArrangedSubview(button(state.layer == .numbers ? "#+=" : "123", label: state.layer == .numbers ? "Symbols" : "Numbers", function: true) { [weak self] in
                        guard let self else { return }; self.select(self.state.layer == .numbers ? .symbols : .numbers)
                    })
                }
            }
            for character in characters {
                let value = String(character)
                let title = state.layer == .letters ? state.shift.label(for: value) : value
                row.addArrangedSubview(button(title, label: title) { [weak self] in self?.type(value) })
            }
            if index == 2 {
                let key = DeleteKeyButton(type: .system)
                configure(key, title: "⌫", label: "Delete", function: true)
                key.addTarget(self, action: #selector(startRepeating), for: .touchDown)
                key.addTarget(self, action: #selector(stopRepeating), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
                row.addArrangedSubview(key)
            }
            if index == 1 && state.layer == .letters {
                let inset = UIStackView(arrangedSubviews: [UIView(), row, UIView()])
                inset.arrangedSubviews[0].widthAnchor.constraint(equalTo: inset.arrangedSubviews[2].widthAnchor).isActive = true
                // Keep this constraint inside the row hierarchy, including during detached construction.
                inset.arrangedSubviews[0].widthAnchor.constraint(equalTo: inset.widthAnchor, multiplier: 0.05).isActive = true
                addArrangedSubview(inset)
            } else { addArrangedSubview(row) }
        }
        let layer = button(state.layer == .letters ? "123" : "ABC", label: state.layer == .letters ? "Numbers" : "Letters", function: true) { [weak self] in
            guard let self else { return }; self.select(self.state.layer == .letters ? .numbers : .letters)
        }
        let space = button("space", label: "Space") { [weak self] in self?.type(" ") }
        let title = returnTitle
        let enter = button(title, label: title, function: true) { [weak self] in self?.type("\n") }
        enter.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        if returnType != .default { enter.backgroundColor = .systemBlue; enter.setTitleColor(.white, for: .normal) }
        let bottom = UIStackView(arrangedSubviews: [layer, globe, mic, space, enter])
        bottom.spacing = 6
        bottom.heightAnchor.constraint(equalToConstant: 42).isActive = true
        for key in [layer, enter] {
            let width = key.widthAnchor.constraint(equalToConstant: 88); width.priority = .defaultHigh; width.isActive = true
        }
        space.widthAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        addArrangedSubview(bottom)
    }

    private var returnTitle: String {
        switch returnType {
        case .go: "go"
        case .google: "Google"
        case .join: "join"
        case .next: "next"
        case .route: "route"
        case .search: "search"
        case .send: "send"
        case .yahoo: "Yahoo"
        case .done: "done"
        case .emergencyCall: "Emergency Call"
        case .continue: "continue"
        default: "return"
        }
    }
    private var characterFill: UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.35, alpha: 1) : .white }
    }
    private func configure(_ key: UIButton, title: String, label: String, function: Bool) {
        key.setTitle(title, for: .normal)
        key.setTitleColor(.label, for: .normal)
        key.accessibilityLabel = label
        key.backgroundColor = function ? .systemGray3 : characterFill
        key.layer.cornerRadius = 8
        key.layer.shadowColor = UIColor.black.cgColor
        key.layer.shadowOpacity = 0.2
        key.layer.shadowOffset = CGSize(width: 0, height: 1)
        key.layer.shadowRadius = 0
        key.titleLabel?.font = .systemFont(ofSize: 22)
    }
    private func button(_ title: String, label: String, function: Bool = false, action: @escaping @MainActor () -> Void) -> UIButton {
        let key = UIButton(type: .system)
        configure(key, title: title, label: label, function: function)
        key.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return key
    }

    @objc private func startRepeating() {
        stopRepeating()
        if deleteState.press(at: clockOrigin.duration(to: clock.now)) { delete() }
        repeatTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    guard let delay = self?.deleteState.delay(at: self?.elapsed ?? .zero) else { return }
                    try await Task.sleep(for: delay)
                    guard !Task.isCancelled, let self else { return }
                    if self.deleteState.tick(at: self.elapsed) { self.delete() }
                }
            } catch { }
        }
    }

    private var elapsed: Duration { clockOrigin.duration(to: clock.now) }

    @objc func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
        deleteState.release()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopRepeating() }
    }
}

/// VoiceOver activation has no physical touch-down event.
@MainActor
private final class DeleteKeyButton: UIButton {
    override func accessibilityActivate() -> Bool {
        sendActions(for: .touchDown)
        sendActions(for: .touchUpInside)
        return true
    }
}
