import XCTest
import ServiceManagement
@testable import GlossPop

// The reconcile decision is pure so the OS-upgrade matrix is testable without the live service.
final class LoginItemTests: XCTestCase {
    func testOfficialBuildIdentityDoesNotDependOnInstallPath() {
        XCTAssertTrue(
            AppIdentity.isOfficialBuild(
                bundleIdentifier: AppIdentity.productionBundleIdentifier,
                teamIdentifier: AppIdentity.productionTeamIdentifier
            )
        )
        XCTAssertFalse(
            AppIdentity.isOfficialBuild(
                bundleIdentifier: AppIdentity.productionBundleIdentifier,
                teamIdentifier: nil
            )
        )
    }

    func testOnlyInstalledDeveloperIDReleaseMayManageLoginItem() {
        XCTAssertTrue(
            AppIdentity.isInstalledRelease(
                bundleIdentifier: AppIdentity.productionBundleIdentifier,
                teamIdentifier: AppIdentity.productionTeamIdentifier,
                bundleURL: URL(fileURLWithPath: AppIdentity.installedBundlePath)
            )
        )

        XCTAssertFalse(
            AppIdentity.isInstalledRelease(
                bundleIdentifier: "com.wanruncong.glosspop.testhost",
                teamIdentifier: nil,
                bundleURL: URL(fileURLWithPath: "/tmp/GlossPop.app")
            )
        )
        XCTAssertFalse(
            AppIdentity.isInstalledRelease(
                bundleIdentifier: AppIdentity.productionBundleIdentifier,
                teamIdentifier: AppIdentity.productionTeamIdentifier,
                bundleURL: URL(fileURLWithPath: "/tmp/GlossPop.app")
            )
        )
        XCTAssertFalse(
            AppIdentity.isInstalledRelease(
                bundleIdentifier: AppIdentity.productionBundleIdentifier,
                teamIdentifier: nil,
                bundleURL: URL(fileURLWithPath: AppIdentity.installedBundlePath)
            )
        )
    }

    func testNoIntentNeverActs() {
        for status: SMAppService.Status in [.enabled, .requiresApproval, .notRegistered, .notFound] {
            XCTAssertEqual(LoginItem.reconcileAction(userWants: false, status: status), .none)
        }
    }

    func testEnabledStaysUntouched() {
        XCTAssertEqual(LoginItem.reconcileAction(userWants: true, status: .enabled), .none)
    }

    func testRequiresApprovalIsNotReRegistered() {
        // register() cannot clear .requiresApproval — only the user can, via System Settings.
        XCTAssertEqual(LoginItem.reconcileAction(userWants: true, status: .requiresApproval), .none)
    }

    func testDroppedRegistrationSelfHeals() {
        XCTAssertEqual(LoginItem.reconcileAction(userWants: true, status: .notRegistered), .register)
        XCTAssertEqual(LoginItem.reconcileAction(userWants: true, status: .notFound), .register)
    }
}
