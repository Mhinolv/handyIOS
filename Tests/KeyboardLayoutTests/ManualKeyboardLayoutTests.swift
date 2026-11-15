import XCTest
@testable import HandyIOS

final class ManualKeyboardLayoutTests: XCTestCase {
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
