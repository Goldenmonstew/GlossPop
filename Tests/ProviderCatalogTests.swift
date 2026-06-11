import XCTest
@testable import GlossPop

final class ProviderCatalogTests: XCTestCase {
    func testPresetsAreWellFormed() {
        var seen = Set<String>()
        for p in ProviderCatalog.presets {
            XCTAssertTrue(seen.insert(p.id).inserted, "duplicate id \(p.id)")
            XCTAssertNotNil(BYOKConfig.url(p.baseURL), "invalid baseURL for \(p.id)")
            XCTAssertTrue(p.apiPath.hasPrefix("/"), "path must be absolute for \(p.id)")
            XCTAssertTrue(p.apiPath.hasSuffix("/chat/completions"), "unexpected path shape for \(p.id)")
            if !p.isLocal { XCTAssertTrue(p.baseURL.hasPrefix("https://"), "cloud preset must be https: \(p.id)") }
        }
    }

    func testEveryPresetRoundTripsThroughMatch() {
        for p in ProviderCatalog.presets {
            XCTAssertEqual(ProviderCatalog.match(base: p.baseURL, path: p.apiPath)?.id, p.id)
        }
    }

    func testRelayOnVendorHostStaysCustom() {
        // Same host but a different path (a relay prefix) must NOT classify as the vendor preset,
        // or its editable endpoint fields would be hidden.
        XCTAssertNil(ProviderCatalog.match(base: "https://api.openai.com", path: "/aigc/v1/chat/completions"))
        XCTAssertNil(ProviderCatalog.match(base: "https://relay.example.com", path: "/v1/chat/completions"))
    }

    func testLocalPresetsAreLoopback() {
        for p in ProviderCatalog.presets where p.isLocal {
            XCTAssertTrue(BYOKConfig.isLocal(p.baseURL), "\(p.id) must be loopback")
        }
    }

    func testEmptyPathDefaultsToStandardRoute() {
        XCTAssertEqual(ProviderCatalog.match(base: "https://api.openai.com", path: "")?.id, "openai")
    }
}
