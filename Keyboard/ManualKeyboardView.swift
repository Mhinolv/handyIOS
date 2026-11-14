import UIKit

/// Uses only the host text proxy through callbacks. No shared storage is needed.
@MainActor
final class ManualKeyboardView: UIStackView {
    var insert: (String) -> Void = { _ in }
    var delete: () -> Void = {}
    var showDictation: () -> Void = {}
    let globe = UIButton(type: .system)
    private let mic = UIButton(type: .system)
    private var letters: [UIButton] = []
    private var shifted = false
    private var repeatTask: Task<Void, Never>?
    private var repeatedDelete = false
    private let shift = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 6
        for characters in ["qwertyuiop", "asdfghjkl", "zxcvbnm"] {
            var keys = characters.map { character in
                let value = String(character)
                let key = button(value, label: value) { [weak self] in
                    guard let self else { return }
                    self.insert(self.shifted ? value.uppercased() : value)
                    self.shifted = false
                    self.updateShift()
                }
                letters.append(key)
                return key
            }
            if characters == "zxcvbnm" {
                configure(shift, title: "⇧", label: "Shift")
                shift.addAction(UIAction { [weak self] _ in
                    self?.shifted.toggle()
                    self?.updateShift()
                }, for: .touchUpInside)
                keys.insert(shift, at: 0)
                let deleteKey = button("⌫", label: "Delete") { [weak self] in
                    guard let self else { return }
                    if !self.repeatedDelete { self.delete() }
                    self.stopRepeating()
                    self.repeatedDelete = false
                }
                deleteKey.addTarget(self, action: #selector(startRepeating), for: .touchDown)
                deleteKey.addTarget(self, action: #selector(stopRepeating), for: [.touchUpOutside, .touchCancel, .touchDragExit])
                keys.append(deleteKey)
            }
            addArrangedSubview(row(keys))
        }
        configure(globe, title: "🌐", label: "Next Keyboard")
        configure(mic, title: "", label: "Dictation")
        mic.addAction(UIAction { [weak self] _ in self?.showDictation() }, for: .touchUpInside)
        let space = button("space", label: "Space") { [weak self] in self?.insert(" ") }
        let bottom = row([globe, mic, space, button("return", label: "Return") { [weak self] in self?.insert("\n") }])
        addArrangedSubview(bottom)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(fullAccess: Bool, needsGlobe: Bool) {
        globe.isHidden = !needsGlobe
        mic.setImage(UIImage(systemName: fullAccess ? "mic.fill" : "mic.slash"), for: .normal)
        mic.accessibilityLabel = fullAccess ? "Dictation" : "Dictation requires Full Access"
        mic.accessibilityHint = fullAccess ? "Show the dictation panel" : "Turn on Full Access in Settings to dictate."
    }

    private func configure(_ button: UIButton, title: String, label: String) {
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = label
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 5
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    private func button(_ title: String, label: String, action: @escaping @MainActor () -> Void) -> UIButton {
        let key = UIButton(type: .system)
        configure(key, title: title, label: label)
        key.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return key
    }

    private func row(_ keys: [UIButton]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: keys)
        row.distribution = .fillEqually
        row.spacing = 4
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return row
    }

    private func updateShift() {
        shift.accessibilityValue = shifted ? "On" : "Off"
        shift.backgroundColor = shifted ? .tertiarySystemFill : .secondarySystemBackground
        for key in letters {
            let title = key.title(for: .normal) ?? ""
            let value = shifted ? title.uppercased() : title.lowercased()
            key.setTitle(value, for: .normal)
            key.accessibilityLabel = value
        }
    }

    @objc private func startRepeating() {
        stopRepeating()
        repeatedDelete = false
        repeatTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                while !Task.isCancelled {
                    self?.repeatedDelete = true
                    self?.delete()
                    try await Task.sleep(for: .milliseconds(80))
                }
            } catch { }
        }
    }

    @objc func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopRepeating() }
    }
}
