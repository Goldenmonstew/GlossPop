import XCTest
@testable import GlossPop

final class AppLaunchModeTests: XCTestCase {
    func testDemoFlagsSelectAnIsolatedLaunchMode() {
        XCTAssertTrue(
            AppLaunchMode(arguments: ["GlossPop", "--demo-card"]).isDemo
        )
        XCTAssertTrue(
            AppLaunchMode(arguments: ["GlossPop", "--demo-vocabulary-export"]).isDemo
        )
        XCTAssertFalse(
            AppLaunchMode(arguments: ["GlossPop", "--dark"]).isDemo
        )
        XCTAssertFalse(
            AppLaunchMode(arguments: ["GlossPop", "--demo-action-error"]).isDemo
        )
        XCTAssertFalse(
            AppLaunchMode(arguments: ["GlossPop", "--demo-expanded"]).isDemo
        )
        XCTAssertFalse(
            AppLaunchMode(arguments: ["GlossPop", "--demo-typo"]).isDemo
        )
        XCTAssertTrue(
            AppLaunchMode(arguments: ["GlossPop", "--demo-vocabulary-recovery"]).isDemo
        )
        XCTAssertFalse(
            AppLaunchMode(arguments: ["GlossPop"]).isDemo
        )
    }
}
