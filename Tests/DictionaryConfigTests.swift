import XCTest
@testable import GlossPop

final class DictionaryConfigTests: XCTestCase {

    // MARK: - Mode semantics (drive the word/phrase routing matrix)

    func testModeFlags() {
        XCTAssertTrue(DictionaryMode.offline.usesSystem)
        XCTAssertFalse(DictionaryMode.offline.autoAI)
        XCTAssertFalse(DictionaryMode.offline.alwaysAI)

        XCTAssertTrue(DictionaryMode.offlineThenAI.usesSystem)
        XCTAssertTrue(DictionaryMode.offlineThenAI.autoAI)
        XCTAssertFalse(DictionaryMode.offlineThenAI.alwaysAI)   // hit → stop at the system entry

        XCTAssertTrue(DictionaryMode.offlinePlusAI.usesSystem)
        XCTAssertTrue(DictionaryMode.offlinePlusAI.autoAI)
        XCTAssertTrue(DictionaryMode.offlinePlusAI.alwaysAI)

        XCTAssertFalse(DictionaryMode.aiOnly.usesSystem)
        XCTAssertTrue(DictionaryMode.aiOnly.autoAI)
        XCTAssertTrue(DictionaryMode.aiOnly.alwaysAI)
    }

    func testUnknownRawValueFallsBackToOffline() {
        XCTAssertNil(DictionaryMode(rawValue: "totally-bogus"))   // getter then defaults to .offline
    }

    // MARK: - Legacy migration mapping

    func testExplicitlyDisabledLegacyDictionaryMapsToAIOnly() {
        XCTAssertEqual(DictionaryConfig.migratedMode(legacyDictionaryOff: true, byokReady: true), .aiOnly)
        XCTAssertEqual(DictionaryConfig.migratedMode(legacyDictionaryOff: true, byokReady: false), .aiOnly)
    }

    func testUpgraderWithConfiguredModelKeepsAutoAIOnMiss() {
        // v0.1.13: system hit → offline, miss → automatic model translation == .offlineThenAI.
        XCTAssertEqual(DictionaryConfig.migratedMode(legacyDictionaryOff: nil, byokReady: true), .offlineThenAI)
        XCTAssertEqual(DictionaryConfig.migratedMode(legacyDictionaryOff: false, byokReady: true), .offlineThenAI)
    }

    func testFreshInstallKeepsPrivacyDefaultOffline() {
        XCTAssertNil(DictionaryConfig.migratedMode(legacyDictionaryOff: nil, byokReady: false))
        XCTAssertNil(DictionaryConfig.migratedMode(legacyDictionaryOff: false, byokReady: false))
    }
}
