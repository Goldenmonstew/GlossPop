import XCTest
@testable import GlossPop

final class AppLaunchModeTests: XCTestCase {
    func testRuntimeGuardKeepsXCTestHostIdle() {
        XCTAssertEqual(
            AppRuntimeGuard.lifecycleDisposition(isXCTestLoaded: true, isTestHostBuild: true),
            .remainIdleForXCTest
        )
    }

    func testRuntimeGuardTerminatesDetachedTestHost() {
        XCTAssertEqual(
            AppRuntimeGuard.lifecycleDisposition(isXCTestLoaded: false, isTestHostBuild: true),
            .terminateDetachedTestHost
        )
    }

    func testRuntimeGuardRunsNormalBuildOutsideXCTest() {
        XCTAssertEqual(
            AppRuntimeGuard.lifecycleDisposition(isXCTestLoaded: false, isTestHostBuild: false),
            .run
        )
    }

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
        for demo in SettingsAssessmentDemo.allCases {
            XCTAssertTrue(
                AppLaunchMode(arguments: ["GlossPop", demo.rawValue]).isDemo,
                "\(demo.rawValue) must stay isolated from production settings"
            )
        }
        XCTAssertFalse(
            AppLaunchMode(arguments: ["GlossPop"]).isDemo
        )
    }
}
