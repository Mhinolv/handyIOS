import XCTest
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
                let mic = try XCTUnwrap(descendants(keyboard).compactMap { $0 as? UIButton }
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
        XCTAssertTrue(keyboard.isHidden)
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
