import XCTest
@testable import GlossPop

final class KeychainTests: XCTestCase {
    func testEachBuildIdentityUsesItsOwnService() {
        XCTAssertEqual(
            Keychain.serviceName(
                bundleIdentifier: "com.wanruncong.glosspop",
                isProductionIdentity: true
            ),
            "com.wanruncong.glosspop"
        )
        XCTAssertEqual(
            Keychain.serviceName(
                bundleIdentifier: "com.wanruncong.glosspop.debug",
                isProductionIdentity: false
            ),
            "com.wanruncong.glosspop.debug"
        )
        XCTAssertEqual(
            Keychain.serviceName(
                bundleIdentifier: "com.wanruncong.glosspop.testhost",
                isProductionIdentity: false
            ),
            "com.wanruncong.glosspop.testhost"
        )
        XCTAssertEqual(
            Keychain.serviceName(bundleIdentifier: nil, isProductionIdentity: false),
            "com.wanruncong.glosspop.unidentified"
        )
    }

    func testProductionBundleIdentifierWithoutProductionIdentityIsIsolated() {
        XCTAssertEqual(
            Keychain.serviceName(
                bundleIdentifier: "com.wanruncong.glosspop",
                isProductionIdentity: false
            ),
            "com.wanruncong.glosspop.nonproduction"
        )
    }
}
