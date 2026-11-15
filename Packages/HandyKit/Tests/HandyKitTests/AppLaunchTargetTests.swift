import XCTest
@testable import HandyKit

final class AppLaunchTargetTests: XCTestCase {
    private let view = LaunchResponderKind.other(answersOpenURL: false)

    /// #31: on iOS 27 the scene comes first in the chain and answers the same selector.
    func testSceneBeforeApplicationNeverGetsADictionary() {
        XCTAssertEqual(AppLaunchTargetRule.target(for: [view, view, view, .scene, .application]),
                       .application(index: 4))
    }

    func testSceneOnlyChainUsesTypedSceneOptions() {
        XCTAssertEqual(AppLaunchTargetRule.target(for: [view, view, .scene]), .scene(index: 2))
    }

    func testApplicationOnlyChainUsesDictionary() {
        XCTAssertEqual(AppLaunchTargetRule.target(for: [view, .application]), .application(index: 1))
    }

    func testUnknownResponderThatAnswersSelectorIsNeverCalled() {
        let unknown = LaunchResponderKind.other(answersOpenURL: true)
        XCTAssertEqual(AppLaunchTargetRule.target(for: [unknown, view]), .none)
        XCTAssertEqual(AppLaunchTargetRule.target(for: [unknown, .scene]), .scene(index: 1))
    }

    func testNoSafeTargetReportsFailure() {
        XCTAssertEqual(AppLaunchTargetRule.target(for: []), .none)
        XCTAssertEqual(AppLaunchTargetRule.target(for: [view, view]), .none)
    }
}
