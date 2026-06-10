import XCTest
@testable import GlossPop

final class StructuredPromptTests: XCTestCase {
    // The bilingual direction must hold: definition in the SECOND language, meaning in the FIRST.
    func testWordPromptDirections() {
        let p = StructuredPrompt.user(kind: .word, source: "serendipity",
                                      firstLanguage: "zh-Hans", secondLanguage: "en")
        XCTAssertTrue(p.contains("\"definition\" MUST be written in en"))
        XCTAssertTrue(p.contains("\"translation\" MUST be the meaning in zh-Hans"))
        XCTAssertTrue(p.contains("Term: serendipity"))
    }

    // Sentence: translation into the resolved target (param 1), explanations in the NATIVE language (param 2)
    // — a zh-first user translating a Chinese sentence to en still reads grammar notes in Chinese.
    func testSentencePromptExplainsInNativeLanguage() {
        let p = StructuredPrompt.user(kind: .sentence, source: "我们一起去公园散步。",
                                      firstLanguage: "en", secondLanguage: "zh-Hans")
        XCTAssertTrue(p.contains("Translate into en"))
        XCTAssertTrue(p.contains("\"explanation\":\"(in zh-Hans)\""))
    }

    func testLongSourceIsTruncated() {
        let long = String(repeating: "a", count: RefinePrompt.maxSourceChars + 500)
        let p = StructuredPrompt.user(kind: .word, source: long, firstLanguage: "zh-Hans", secondLanguage: "en")
        XCTAssertLessThan(p.count, RefinePrompt.maxSourceChars + 600)   // template + capped source only
    }
}
