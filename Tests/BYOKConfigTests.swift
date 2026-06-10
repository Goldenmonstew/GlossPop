import XCTest
@testable import GlossPop

final class BYOKConfigTests: XCTestCase {
    // The privacy P0: a scheme-less loopback URL must NOT be classified as cloud.
    func testSchemeLessLocalhostIsLocal() {
        XCTAssertTrue(BYOKConfig.isLocal("localhost:11434/v1"))
        XCTAssertTrue(BYOKConfig.isLocal("http://127.0.0.1:11434/v1"))
        XCTAssertTrue(BYOKConfig.isLocal("https://localhost/v1"))
    }

    func testCloudIsNotLocal() {
        XCTAssertFalse(BYOKConfig.isLocal("api.openai.com/v1"))
        XCTAssertFalse(BYOKConfig.isLocal("https://relay.example.com/aigc/v1"))
    }

    func testURLValidation() {
        XCTAssertNotNil(BYOKConfig.url("api.openai.com/v1"))      // scheme auto-prefixed
        XCTAssertNotNil(BYOKConfig.url("https://api.openai.com/v1"))
        XCTAssertNil(BYOKConfig.url(""))                          // empty
        XCTAssertNil(BYOKConfig.url("not a url"))                 // space → invalid
        XCTAssertNil(BYOKConfig.url("ftp://example.com"))         // wrong scheme
    }

    func testNormalizePrefixesHTTPS() {
        XCTAssertEqual(BYOKConfig.normalized("api.openai.com/v1"), "https://api.openai.com/v1")
        XCTAssertEqual(BYOKConfig.normalized("http://x/v1"), "http://x/v1")   // keeps explicit scheme
        XCTAssertEqual(BYOKConfig.normalized("  https://x/v1  "), "https://x/v1") // trims
    }

    func testHostExtraction() {
        XCTAssertEqual(BYOKConfig.host("relay.example.com/aigc/v1"), "relay.example.com")
    }
}
