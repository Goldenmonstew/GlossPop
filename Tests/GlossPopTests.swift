import XCTest
@testable import GlossPop

@MainActor
final class GlossPopTests: XCTestCase {
    // M1 skeleton smoke test — proves the test target builds & links against the app.
    func testAppStateVersionString() {
        let state = AppState()
        XCTAssertTrue(state.versionString.hasPrefix("v"))
    }
}
