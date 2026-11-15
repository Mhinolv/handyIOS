import XCTest
import HandyKit
@testable import HandyIOS

final class ManualKeyboardLayoutTests: XCTestCase {
    @MainActor
    func testIdleAndDeniedAccessShowKeyRows() throws {
        for name in ["keyboard-idle", "keyboard-full-access-off"] {
            let controller = KeyboardViewController()
            controller.snapshotName = name
            controller.loadViewIfNeeded()
            controller.viewWillAppear(false)
            let keyboard = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? ManualKeyboardView }.first)
            XCTAssertFalse(keyboard.isHidden, "Key rows must show for \(name)")
            if name == "keyboard-full-access-off" {
                let mic = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIButton }
                    .first { $0.accessibilityLabel == "Dictation requires Full Access" })
                XCTAssertFalse(mic.isEnabled)
                XCTAssertEqual(mic.accessibilityHint, "Turn on Full Access in Settings to dictate.")
            }
            controller.viewWillDisappear(false)
        }
    }

    @MainActor
    func testCompletedDictationReturnsToKeyRows() async throws {
        let controller = KeyboardViewController()
        controller.snapshotName = "keyboard-listening"
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        let keyboard = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? ManualKeyboardView }.first)
        XCTAssertFalse(keyboard.isHidden)
        controller.showInserted()
        try await Task.sleep(for: .milliseconds(1700))
        XCTAssertFalse(keyboard.isHidden)
        // Closing the keyboard cancels the timer, but must retain the idle rows.
        controller.viewWillAppear(false)
        controller.showInserted()
        controller.viewWillDisappear(false)
        XCTAssertFalse(keyboard.isHidden)
    }

    @MainActor
    func testTopBarKeepsKeysAndZonesAt375Points() throws {
        // Ignore subpixel rounding. A one-point error must still fail.
        let tolerance: CGFloat = 0.5
        let controller = KeyboardViewController()
        controller.snapshotName = "keyboard-idle"
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: KeyboardLayout.height)
        for name in ["keyboard-idle", "keyboard-opening", "keyboard-launch-failed", "keyboard-listening",
                     "keyboard-transcribing", "keyboard-chip", "keyboard-inserted", "keyboard-recovery",
                     "keyboard-full-access-off"] {
            controller.snapshotName = name
            controller.viewWillAppear(false)
            controller.view.layoutIfNeeded()
            let views = descendants(controller.view)
            let mic = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "dictation-mic" })
            let status = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "dictation-status" })
            let chip = try XCTUnwrap(views.first { $0.accessibilityIdentifier == "dictation-chip" })
            let keys = try XCTUnwrap(views.compactMap { $0 as? ManualKeyboardView }.first)
            let micFrame = mic.convert(mic.bounds, to: controller.view)
            XCTAssertEqual(micFrame.midX, 187.5, accuracy: tolerance, name)
            XCTAssertEqual(micFrame.width, 64, accuracy: tolerance)
            XCTAssertEqual(micFrame.height, 36, accuracy: tolerance)
            for leading in [status, chip] {
                let frame = leading.convert(leading.bounds, to: controller.view)
                XCTAssertLessThanOrEqual(frame.width, 140 + tolerance, name)
                XCTAssertLessThanOrEqual(frame.maxX, micFrame.minX - 8 + tolerance, name)
            }
            for button in views.compactMap({ $0 as? UIButton }) where
                button.title(for: .normal) == "Insert" || button.accessibilityLabel == "Hide dictation" {
                XCTAssertGreaterThanOrEqual(button.convert(button.bounds, to: controller.view).minX,
                                            micFrame.maxX + 8 - tolerance, name)
            }
            XCTAssertFalse(keys.isHidden, name)
            XCTAssertEqual(keys.arrangedSubviews.count, 4)
            XCTAssertGreaterThanOrEqual(keys.convert(keys.bounds, to: controller.view).minY,
                                        micFrame.maxY - tolerance, name)
            XCTAssertEqual(controller.view.bounds.height, KeyboardLayout.height, accuracy: tolerance, name)
            XCTAssertFalse(descendants(keys).contains { $0.accessibilityIdentifier == "dictation-mic" })
            let letter = try XCTUnwrap(descendants(keys).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "q" })
            XCTAssertTrue(letter.isEnabled, name)
            XCTAssertEqual(status.isHidden, name == "keyboard-chip")
            let statusLabel = try XCTUnwrap(status as? UILabel)
            XCTAssertEqual(statusLabel.numberOfLines, 2)
            XCTAssertEqual(statusLabel.lineBreakMode, .byTruncatingTail)
            controller.viewWillDisappear(false)
        }
    }

    @MainActor
    func testTranscribingReadyDismissRestoresMic() throws {
        let session = DictationSession(storage: KeyboardTestStorage())
        let request = try session.request()
        XCTAssertTrue(try session.startRecording(requestID: request.id))
        XCTAssertTrue(try session.finishCapture(requestID: request.id))
        let controller = KeyboardViewController()
        controller.snapshotName = "keyboard-idle"
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        let views = descendants(controller.view)
        let mic = try XCTUnwrap(views.compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "dictation-mic" })
        let status = try XCTUnwrap(views.compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "dictation-status" })
        controller.pollForTesting(session: session)
        XCTAssertFalse(mic.isEnabled)
        XCTAssertEqual(status.text, "Transcribing…")
        XCTAssertTrue(try session.publish(text: "A result for another field", requestID: request.id))
        controller.pollForTesting(session: session)
        XCTAssertTrue(mic.isEnabled, "Ready must clear the disabled transcription spinner")
        XCTAssertEqual(mic.image(for: .normal), UIImage(systemName: "mic.fill"))
        XCTAssertEqual(status.text, "Tap the mic to dictate")
        XCTAssertTrue(status.isHidden)
        let dismiss = try XCTUnwrap(views.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Hide dictation" })
        dismiss.sendActions(for: .touchUpInside)
        XCTAssertFalse(status.isHidden)
        XCTAssertEqual(status.text, "Tap the mic to dictate")
        XCTAssertTrue(mic.isEnabled)
        controller.pollForTesting(session: session)
        XCTAssertFalse(status.isHidden, "Dismiss must survive the next poll")
        XCTAssertTrue(mic.isEnabled)
        controller.viewWillDisappear(false)
    }

    @MainActor
    func testNilDocumentIdentifierShowsChipAndAllowsExplicitInsert() throws {
        let session = DictationSession(storage: KeyboardTestStorage())
        let request = try session.request()
        XCTAssertTrue(try session.startRecording(requestID: request.id))
        XCTAssertTrue(try session.finishCapture(requestID: request.id))
        XCTAssertTrue(try session.publish(text: "Unknown host", requestID: request.id))
        let consumer = ResultConsumer()
        let leading = UIView()
        let trailing = UIView()
        var visible = false
        consumer.install(leading: leading, trailing: trailing) { visible = $0 }
        let proxy = NilIdentifierProxy()
        consumer.begin(id: request.id, proxy: proxy)
        var inserted = false
        XCTAssertFalse(try consumer.consume(session: session, proxy: proxy) { inserted = true })
        XCTAssertTrue(visible)
        XCTAssertEqual(proxy.output, "")
        let button = try XCTUnwrap(descendants(trailing).compactMap { $0 as? UIButton }
            .first { $0.configuration?.title == "Insert" })
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(inserted)
        XCTAssertFalse(visible)
        XCTAssertEqual(proxy.output, "Unknown host")
        XCTAssertEqual(try session.snapshot().state, .idle)
    }

    @MainActor
    func testListeningIndicatorAndDeniedMicColors() throws {
        let controller = KeyboardViewController()
        for style in [UIUserInterfaceStyle.light, .dark] {
            controller.overrideUserInterfaceStyle = style
            controller.snapshotName = "keyboard-listening"
            controller.loadViewIfNeeded()
            controller.viewWillAppear(false)
            let views = descendants(controller.view)
            let indicator = try XCTUnwrap(views.compactMap { $0 as? UIImageView }
                .first { $0.accessibilityIdentifier == "dictation-status-indicator" })
            XCTAssertFalse(indicator.isHidden)
            XCTAssertEqual(indicator.image, UIImage(systemName: "circle.fill"))
            XCTAssertEqual(indicator.tintColor, .systemRed)
            controller.snapshotName = "keyboard-full-access-off"
            controller.viewWillAppear(false)
            XCTAssertTrue(indicator.isHidden)
            let mic = try XCTUnwrap(views.compactMap { $0 as? UIButton }
                .first { $0.accessibilityIdentifier == "dictation-mic" })
            XCTAssertFalse(mic.isEnabled)
            XCTAssertEqual(mic.tintAdjustmentMode, .normal)
            let traits = UITraitCollection(userInterfaceStyle: style)
            XCTAssertEqual(mic.tintColor.resolvedColor(with: traits), UIColor.label.resolvedColor(with: traits))
            XCTAssertNotEqual(mic.tintColor.resolvedColor(with: traits), mic.backgroundColor?.resolvedColor(with: traits))
            controller.viewWillDisappear(false)
        }
    }

    @MainActor
    func testInsertTitleFitsOneLineAt375Points() throws {
        let controller = KeyboardViewController()
        controller.snapshotName = "keyboard-chip"
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: KeyboardLayout.height)
        controller.view.layoutIfNeeded()
        let button = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIButton }
            .first { ($0.configuration?.title ?? $0.title(for: .normal)) == "Insert" })
        button.layoutIfNeeded()
        let label = try XCTUnwrap(button.titleLabel)
        XCTAssertEqual(label.numberOfLines, 1)
        let title = try XCTUnwrap(label.text)
        let font = try XCTUnwrap(label.font)
        let size = (title as NSString).size(withAttributes: [.font: font])
        XCTAssertLessThanOrEqual(size.width, label.bounds.width + 0.5)
        XCTAssertLessThanOrEqual(size.height, label.bounds.height + 0.5)
        XCTAssertLessThanOrEqual(label.bounds.height, button.bounds.height + 0.5)
        controller.viewWillDisappear(false)
    }

    @MainActor
    func testLaunchResultHasDistinctFailureAndCanRecover() throws {
        let controller = KeyboardViewController()
        controller.snapshotName = "keyboard-idle"
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        let label = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UILabel }
            .first { $0.accessibilityIdentifier == "dictation-status" })
        controller.showLaunchResult(false)
        XCTAssertEqual(label.text, "Handy did not open. Open it, then try again.")
        controller.showInserted()
        XCTAssertEqual(label.text, "Inserted")
        controller.viewWillDisappear(false)
    }

    @MainActor
    func testAllLayersTypeWithoutFullAccess() throws {
        let keyboard = ManualKeyboardView()
        var text = ""
        keyboard.insert = { text += $0 }
        keyboard.update(fullAccess: false, needsGlobe: true)
        for (name, rows) in [("keyboard-abc", ["qwertyuiop", "asdfghjkl", "zxcvbnm"]),
                             ("keyboard-numbers", ["1234567890", "-/:;()$&@\"", ".,?!'"]),
                             ("keyboard-symbols", ["[]{}#%^*+=", "_\\|~<>€£¥•", ".,?!'"])] {
            keyboard.showSnapshot(name)
            for character in rows.joined() {
                let key = try XCTUnwrap(descendants(keyboard).compactMap { $0 as? UIButton }
                    .first { $0.accessibilityLabel == String(character) })
                XCTAssertTrue(key.isEnabled)
                key.sendActions(for: .touchUpInside)
            }
        }
        XCTAssertEqual(text, "qwertyuiopasdfghjklzxcvbnm1234567890-/:;()$&@\".,?!'[]{}#%^*+=_\\|~<>€£¥•.,?!'")
    }

    @MainActor
    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    @MainActor
    func testDetachedKeyboardCanBuildAndRebuildEveryLayer() {
        let keyboard = ManualKeyboardView()
        for _ in 0..<3 {
            for name in ["keyboard-shift", "keyboard-caps", "keyboard-numbers", "keyboard-symbols", "keyboard-search"] {
                keyboard.showSnapshot(name)
                keyboard.update(fullAccess: false, needsGlobe: true)
                keyboard.update(fullAccess: false, needsGlobe: false)
                keyboard.frame = CGRect(x: 0, y: 0, width: 370, height: 204)
                keyboard.layoutIfNeeded()
                checkConstraints(in: keyboard)
                XCTAssertEqual(keyboard.arrangedSubviews.count, 4)
            }
        }
    }

    @MainActor
    private func checkConstraints(in view: UIView) {
        for constraint in view.constraints where constraint.isActive {
            guard let first = constraint.firstItem as? UIView,
                  let second = constraint.secondItem as? UIView else { continue }
            XCTAssertTrue(ancestors(first).contains { candidate in ancestors(second).contains { $0 === candidate } },
                          "Active constraint has no common ancestor: \(constraint)")
        }
        for child in view.subviews { checkConstraints(in: child) }
    }

    @MainActor
    private func ancestors(_ view: UIView) -> [UIView] {
        var result = [view]
        var parent = view.superview
        while let current = parent { result.append(current); parent = current.superview }
        return result
    }
}

private final class KeyboardTestStorage: SessionStorage {
    private var data: Data?
    func transaction<T>(_ body: (inout Data?) throws -> T) throws -> T { try body(&data) }
}

/// Model a host that returns nil from the Objective-C getter despite UIKit's nonoptional UUID declaration.
@MainActor
private final class NilIdentifierProxy: NSObject, UITextDocumentProxy {
    var output = ""
    var documentContextBeforeInput: String? { nil }
    var documentContextAfterInput: String? { nil }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID {
        XCTFail("Do not read the nonoptional Swift UUID bridge")
        return UUID()
    }
    override func value(forKey key: String) -> Any? {
        if key == "documentIdentifier" { return nil }
        return super.value(forKey: key)
    }
    var hasText: Bool { !output.isEmpty }
    func insertText(_ text: String) { output += text }
    func deleteBackward() { if !output.isEmpty { output.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
}
