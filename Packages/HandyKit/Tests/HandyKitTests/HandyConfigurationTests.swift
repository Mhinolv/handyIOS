import XCTest
@testable import HandyKit

final class HandyConfigurationTests: XCTestCase {
    func testBothTargetsDeclareSharedAppGroup() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            root.deleteLastPathComponent()
        }
        for path in ["App/HandyIOS.entitlements", "Keyboard/HandyKeyboard.entitlements"] {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            XCTAssertEqual(
                plist["com.apple.security.application-groups"] as? [String],
                [HandyConfiguration.appGroupIdentifier],
                path
            )
        }
    }

    func testSharedIdentity() {
        XCTAssertEqual(HandyConfiguration.displayName, "Handy")
        XCTAssertEqual(HandyConfiguration.appGroupIdentifier, "group.com.mhinolv.handyios")
    }
}
