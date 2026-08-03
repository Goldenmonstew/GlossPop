import XCTest
@testable import GlossPop

final class StructuredPromptTests: XCTestCase {
    // The bilingual direction must hold: definition in the SECOND language, meaning in the FIRST.
    // Codes are rendered as written language NAMES so the model honours them reliably.
    func testWordPromptDirections() {
        let p = StructuredPrompt.user(kind: .word, source: "serendipity",
                                      firstLanguage: "zh-Hans", secondLanguage: "en")
        XCTAssertTrue(p.contains("\"definition\" MUST be written in English"))
        XCTAssertTrue(p.contains("\"translation\" MUST be the meaning in Simplified Chinese"))
        XCTAssertTrue(p.contains("Term: serendipity"))
        XCTAssertFalse(p.contains("zh-Hans"))   // no raw BCP-47 codes leak into the prompt
    }

    // Sentence: translation into the resolved target (param 1), analysis prose in the NATIVE language (param 2)
    // — a zh-first user translating a Chinese sentence to en still reads grammar notes in Chinese.
    func testSentencePromptExplainsInNativeLanguage() {
        let p = StructuredPrompt.user(kind: .sentence, source: "我们一起去公园散步。",
                                      firstLanguage: "en", secondLanguage: "zh-Hans")
        XCTAssertTrue(p.contains("into English"))
        XCTAssertTrue(p.contains("\"refinedTranslation\" in English"))
        XCTAssertTrue(p.contains("\"refinedTranslation\":\"(in English)\""))
        XCTAssertFalse(p.contains("\"refinedTranslation\":\"(in Simplified Chinese)\""))
        XCTAssertFalse(p.contains("zh-Hans"))   // names, not BCP-47 codes
        // Every analysis field — including notes — is requested in the native language BY NAME, and notes
        // carry the same per-field "(in …)" marker the grammar points use: a bare [] template let notes
        // drift back to English on long multi-sentence inputs (verified via live calls). Notes are also
        // scoped to genuinely useful content, not generic filler about the structure/translation.
        XCTAssertTrue(p.contains("every \"notes\" entry in Simplified Chinese"))
        XCTAssertTrue(p.contains("\"notes\":[\"(in Simplified Chinese)\"]"))
        XCTAssertTrue(p.contains("\"point\":\"(in Simplified Chinese)\""))
        XCTAssertTrue(p.contains("\"explanation\":\"(in Simplified Chinese)\""))
        // Grammar points must surface useful keywords/structures, not trivial part-of-speech labels.
        XCTAssertTrue(p.contains("Do NOT label ordinary words with their part of speech"))
        // …but the S/V/O slots stay verbatim from the source, so they aren't pinned to a language.
        XCTAssertTrue(p.contains("exact words from the original sentence"))
    }

    // Each native language gets ITS OWN worked example (lifts weaker models); it's withheld when the
    // translation target isn't the reader's language, and for languages that have no example.
    func testSentencePromptWorkedExampleGating() {
        let zh = StructuredPrompt.user(kind: .sentence, source: "The cat sat.", firstLanguage: "zh-Hans", secondLanguage: "zh-Hans")
        XCTAssertTrue(zh.contains("Worked example"))
        XCTAssertTrue(zh.contains("burn through its runway"))   // the Chinese example's content
        let ja = StructuredPrompt.user(kind: .sentence, source: "The cat sat.", firstLanguage: "ja", secondLanguage: "ja")
        XCTAssertTrue(ja.contains("Worked example"))
        XCTAssertTrue(ja.contains("cliff"))                     // the Japanese example's content
        XCTAssertFalse(ja.contains("burn through its runway"))  // not the Chinese one
        // target != native (translating OUT of the native language) → no example (its translation wouldn't match)
        let cross = StructuredPrompt.user(kind: .sentence, source: "他在看书。", firstLanguage: "en", secondLanguage: "zh-Hans")
        XCTAssertFalse(cross.contains("Worked example"))
        // a language with no authored example falls back to the plain spec
        let it = StructuredPrompt.user(kind: .sentence, source: "Il gatto dorme.", firstLanguage: "it", secondLanguage: "it")
        XCTAssertFalse(it.contains("Worked example"))
    }

    func testLongSourceIsTruncated() {
        let long = String(repeating: "a", count: RefinePrompt.maxSourceChars + 500)
        let p = StructuredPrompt.user(kind: .word, source: long, firstLanguage: "zh-Hans", secondLanguage: "en")
        XCTAssertLessThan(p.count, RefinePrompt.maxSourceChars + 600)   // template + capped source only
    }
}
