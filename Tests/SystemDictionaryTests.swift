import XCTest
@testable import GlossPop

// Fixtures are REAL DCSCopyTextDefinition outputs captured on-device (牛津英汉汉英词典 + Oxford),
// so these tests pin the parsing without depending on which dictionaries the test machine enables.
final class SystemDictionaryTests: XCTestCase {

    // MARK: - 汉英 (no " | " separators) layout

    func testChineseEntryUsesTermAsHeadwordAndExtractsPinyin() {
        let raw = "学习 xuéxí verb ① （获取知识技能） study▸ 学习文化 learn to read and write ▸ 在实践中学习 learn through practice ② （效仿） emulate▸ 学习他的英雄事迹 learn from his heroic deeds"
        let entry = SystemDictionary.parse(raw: raw, term: "学习")
        XCTAssertEqual(entry?.headword, "学习")
        XCTAssertEqual(entry?.pronunciation, "xuéxí")
        // The body must NOT duplicate the headword/pinyin, and senses/examples get their own lines.
        XCTAssertEqual(entry?.body.hasPrefix("verb"), true)
        XCTAssertEqual(entry?.body.contains("\n① "), true)
        XCTAssertEqual(entry?.body.contains("\n② "), true)
        XCTAssertEqual(entry?.body.contains("▸"), false)   // ▸ examples → "· " lines
        XCTAssertEqual(entry?.hasCJK, true)
    }

    func testHuiyiRegressionFromUserScreenshot() {
        // Real DCS output for 会议 — the user's screenshot showed this ENTIRE string rendered as the
        // bold headline plus the body duplicated below it. Pin the fixed parse.
        let raw = "会议 huìyì noun ① （指集会） meeting▸ 出席会议 attend a meeting ▸ 结束会议 close a meeting ▸ 举行会议 hold a meeting ▸ 宣布会议开始/结束 declare a meeting open/closed ▸ 召开会议 call a meeting ▸ 会议记录 minutes ▸ 会议日程 agenda of a meeting ▸ 紧急会议 urgent meeting ▸ 全体会议 plenary session ▸ 预备会议 preparatory meeting ② （指机构） council▸ 部长会议 council of ministers → 中国人民政治协商会议"
        let entry = SystemDictionary.parse(raw: raw, term: "会议")
        XCTAssertEqual(entry?.headword, "会议")          // NOT the whole entry
        XCTAssertEqual(entry?.pronunciation, "huìyì")
        XCTAssertEqual(entry?.body.hasPrefix("noun"), true)   // headword/pinyin not duplicated into the body
        XCTAssertEqual(entry?.body.contains("\n① "), true)
        XCTAssertEqual(entry?.body.contains("\n② "), true)
        XCTAssertEqual(entry?.body.contains("· 出席会议 attend a meeting"), true)
    }

    func testMultiSyllablePinyinIsFullyExtracted() {
        let raw = "人工智能 rénɡōnɡ zhìnénɡ noun ［Computing］ artificial intelligence (AI)▸ 人工智能语言 artificial intelligence language"
        let entry = SystemDictionary.parse(raw: raw, term: "人工智能")
        XCTAssertEqual(entry?.headword, "人工智能")
        XCTAssertEqual(entry?.pronunciation, "rénɡōnɡ zhìnénɡ")
        XCTAssertEqual(entry?.body.hasPrefix("noun"), true)
    }

    func testIdiomHyphenatedPinyin() {
        let raw = "一举两得 yījǔ-liǎnɡdé idiom kill two birds with one stone"
        let entry = SystemDictionary.parse(raw: raw, term: "一举两得")
        XCTAssertEqual(entry?.headword, "一举两得")
        XCTAssertEqual(entry?.pronunciation, "yījǔ-liǎnɡdé")
        XCTAssertEqual(entry?.body, "idiom kill two birds with one stone")
    }

    func testSenseLetterMarkerStopsPinyinExtraction() {
        let raw = "高兴 ɡāoxìnɡ A. adjective happy▸ 高兴得跳起来 jump for joy B. verb be willing to"
        let entry = SystemDictionary.parse(raw: raw, term: "高兴")
        XCTAssertEqual(entry?.pronunciation, "ɡāoxìnɡ")   // "A." is not a pinyin token
        XCTAssertEqual(entry?.body.hasPrefix("A. adjective"), true)
    }

    func testPlainASCIIWordsAreNeverEatenAsPinyin() {
        // A pipe-less entry whose body starts with ASCII words must keep them in the body.
        let raw = "电脑 diànnǎo noun computer▸ 个人电脑 personal computer"
        let entry = SystemDictionary.parse(raw: raw, term: "电脑")
        XCTAssertEqual(entry?.pronunciation, "diànnǎo")
        XCTAssertEqual(entry?.body.hasPrefix("noun computer"), true)
    }

    func testTraditionalLookupReturningSimplifiedEntryKeepsTermAsHeadword() {
        // raw does NOT start with the (traditional) term → no prefix strip, but headword stays the term.
        let raw = "学习 xuéxí verb ① （获取知识技能） study"
        let entry = SystemDictionary.parse(raw: raw, term: "學習")
        XCTAssertEqual(entry?.headword, "學習")
        XCTAssertEqual(entry?.pronunciation, "")            // first token 学习 is CJK → no pinyin strip
        XCTAssertEqual(entry?.body.contains("学习 xuéxí"), true)
    }

    // MARK: - Oxford (" | ") layout — unchanged behavior

    func testOxfordEntryParsesHeadwordPronBody() {
        let raw = "serendipity | BrE ˌsɛr(ə)nˈdɪpɪti, AmE ˌsɛrənˈdɪpədi | noun the occurrence of events by chance in a happy way"
        let entry = SystemDictionary.parse(raw: raw, term: "serendipity")
        XCTAssertEqual(entry?.headword, "serendipity")
        XCTAssertEqual(entry?.pronunciation, "BrE ˌsɛr(ə)nˈdɪpɪti, AmE ˌsɛrənˈdɪpədi")
        XCTAssertEqual(entry?.body.hasPrefix("noun"), true)
        XCTAssertEqual(entry?.hasCJK, false)
    }

    func testPhraseGuardRejectsFirstWordOnlyHit() {
        // Multi-word selection where DCS returned just the first word's entry → must be a miss.
        let raw = "ice | BrE ʌɪs, AmE aɪs | noun frozen water"
        XCTAssertNil(SystemDictionary.parse(raw: raw, term: "ice sculpture festival"))
    }

    func testPhraseGuardAcceptsExactPhraseHeadword() {
        let raw = "ice cream | BrE ˌʌɪs ˈkriːm | noun a frozen dessert"
        let entry = SystemDictionary.parse(raw: raw, term: "Ice Cream")   // case-insensitive
        XCTAssertEqual(entry?.headword, "ice cream")
    }

    func testPhraseGuardIsLenientAboutPunctuationApostrophesAndWhitespace() {
        let raw = "ice cream | BrE ˌʌɪs ˈkriːm | noun a frozen dessert"
        XCTAssertNotNil(SystemDictionary.parse(raw: raw, term: "ice cream."))    // trailing punctuation
        XCTAssertNotNil(SystemDictionary.parse(raw: raw, term: "ice  cream"))    // whitespace run
        let curly = "rock 'n' roll | BrE | noun music genre"
        XCTAssertNotNil(SystemDictionary.parse(raw: curly, term: "rock \u{2019}n\u{2019} roll")) // curly apostrophes
        let accent = "crème brûlée | BrE | noun custard dessert"
        XCTAssertNotNil(SystemDictionary.parse(raw: accent, term: "creme brulee")) // diacritic-insensitive
    }

    func testPipelessPhraseGuardRejectsFirstWordHit() {
        // A pipe-less entry that opens with only the FIRST word of a spaced phrase is a sub-term hit.
        XCTAssertNil(SystemDictionary.parse(raw: "ice noun frozen water", term: "ice sculpture festival"))
    }

    func testPipelessExactPhraseAccepted() {
        let e = SystemDictionary.parse(raw: "ice cream noun a frozen dessert", term: "ice cream")
        XCTAssertEqual(e?.headword, "ice cream")
        XCTAssertEqual(e?.body.hasPrefix("noun"), true)
    }

    // MARK: - Body line classification (drives the Look Up-style card typography)

    func testClassifyLines() {
        XCTAssertEqual(SystemDictionary.classifyLine("   · 出席会议 attend a meeting"), .example)
        XCTAssertEqual(SystemDictionary.classifyLine("① (指集会) meeting"), .sense)
        XCTAssertEqual(SystemDictionary.classifyLine("2. the sport of racing."), .sense)
        XCTAssertEqual(SystemDictionary.classifyLine("noun"), .posHeader)
        XCTAssertEqual(SystemDictionary.classifyLine("verb ① (获取知识技能) study"), .posHeader)
        XCTAssertEqual(SystemDictionary.classifyLine("ORIGIN late Middle English"), .sectionHeader)
        XCTAssertEqual(SystemDictionary.classifyLine("PHRASAL VERBS run into"), .sectionHeader)
        XCTAssertEqual(SystemDictionary.classifyLine("idiom kill two birds with one stone"), .plain)
        XCTAssertEqual(SystemDictionary.classifyLine("某个普通行"), .plain)
    }

    // MARK: - formatBody bilingual + Oxford rules

    func testFormatBodyCircledNumbersAndExampleMarkers() {
        let body = SystemDictionary.formatBody("verb ① （获取知识技能） study▸ 学习文化 learn ② （效仿） emulate‣ 学习他 learn from him")
        XCTAssertEqual(body.contains("\n① "), true)
        XCTAssertEqual(body.contains("\n② "), true)
        XCTAssertEqual(body.contains("· 学习文化"), true)
        XCTAssertEqual(body.contains("· 学习他"), true)
    }

    func testFormatBodyOxfordNumberedSensesAndBullets() {
        let body = SystemDictionary.formatBody("noun mass noun: 1 the action of running. 2 the sport of racing. • a related sub-sense.")
        XCTAssertEqual(body.contains("\n2. "), true)
        XCTAssertEqual(body.contains("\n   · a related sub-sense"), true)
    }
}
