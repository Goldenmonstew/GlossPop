import XCTest
@testable import GlossPop

final class TargetLanguageTests: XCTestCase {
    private func lang(_ id: String) -> Locale.Language { Locale.Language(identifier: id) }

    func testChineseScriptDifferenceIsAValidConversion() {
        // zh-Hans → zh-Hant must NOT be treated as "same language".
        XCTAssertFalse(TargetLanguage.sameLanguage(lang("zh-Hans"), lang("zh-Hant")))
        XCTAssertFalse(TargetLanguage.sameLanguage(lang("zh-Hant"), lang("zh-Hans")))
    }

    func testSameScriptChineseIsSame() {
        XCTAssertTrue(TargetLanguage.sameLanguage(lang("zh-Hans"), lang("zh-Hans")))
    }

    func testDifferentBaseLanguagesDiffer() {
        XCTAssertFalse(TargetLanguage.sameLanguage(lang("en"), lang("fr")))
        XCTAssertFalse(TargetLanguage.sameLanguage(lang("en"), lang("zh-Hans")))
    }

    func testSameNonChineseLanguageIsSame() {
        XCTAssertTrue(TargetLanguage.sameLanguage(lang("en"), lang("en-US")))
    }

    // MARK: - First/second-language defaults (injected preferred lists — no real Locale dependency)

    func testDefaultFirstPrefersChineseOverEnglishUILanguage() {
        // Chinese native running macOS in English: [en-GB, zh-Hans-GB] must NOT yield first=en
        // (that inverts the AI dictionary's 释义/意思 direction).
        XCTAssertEqual(TargetLanguage.defaultFirst(preferred: ["en-GB", "zh-Hans-GB"]), "zh-Hans")
        XCTAssertEqual(TargetLanguage.defaultFirst(preferred: ["en-US", "zh-Hant-TW"]), "zh-Hant")
    }

    func testDefaultFirstFallsBackToSystemPrimaryWithoutChinese() {
        XCTAssertEqual(TargetLanguage.defaultFirst(preferred: ["fr-FR", "en-US"]), "fr")
        XCTAssertEqual(TargetLanguage.defaultFirst(preferred: []), "en")
    }

    func testDefaultSecondSkipsVariantsOfFirst() {
        XCTAssertEqual(TargetLanguage.defaultSecond(for: "zh-Hans", preferred: ["zh-Hans-CN", "en-CN"]), "en")
        XCTAssertEqual(TargetLanguage.defaultSecond(for: "en", preferred: ["en-GB", "zh-Hans-GB"]), "zh-Hans")
    }

    func testDefaultSecondFallbackWhenAllPreferredMatchFirst() {
        XCTAssertEqual(TargetLanguage.defaultSecond(for: "zh-Hans", preferred: ["zh-Hans-CN"]), "en")
        XCTAssertEqual(TargetLanguage.defaultSecond(for: "en", preferred: ["en-US"]), "zh-Hans")
    }
}
