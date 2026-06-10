import XCTest
@testable import GlossPop

final class RefinePromptTests: XCTestCase {
    func testTargetSubstitutedBeforeTextSoSourceLiteralSurvives() {
        // Source contains a literal "$target" — it must NOT be rewritten by the $target substitution.
        let msgs = RefinePrompt.messages(
            source: "set $target in Makefile", draft: "", targetCode: "zh-Hans",
            customSystem: "", customUser: "Translate to $target: $text")
        let user = msgs.last?["content"] ?? ""
        XCTAssertTrue(user.contains("Translate to zh-Hans:"), "template $target should be filled")
        XCTAssertTrue(user.contains("set $target in Makefile"), "source's literal $target must survive")
    }

    func testWhitespaceOnlyCustomPromptFallsBackToBuiltin() {
        let msgs = RefinePrompt.messages(
            source: "hello", draft: "", targetCode: "zh-Hans",
            customSystem: "   \n ", customUser: "")
        XCTAssertEqual(msgs.first?["content"], RefinePrompt.system, "blank custom prompt → built-in system prompt")
        XCTAssertEqual(msgs.count, 2)
    }

    func testCustomUserOnlyOmitsSystemMessage() {
        let msgs = RefinePrompt.messages(
            source: "hi", draft: "", targetCode: "ja",
            customSystem: "", customUser: "翻译成 $target:$text")
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs.first?["role"], "user")
        XCTAssertEqual(msgs.first?["content"], "翻译成 ja:hi")
    }

    func testExpandedResultIsCappedWhenTemplateRepeatsText() {
        let big = String(repeating: "a", count: 50_000)
        let msgs = RefinePrompt.messages(
            source: big, draft: "", targetCode: "en",
            customSystem: "", customUser: "$text $text $text")
        let user = msgs.last?["content"] ?? ""
        XCTAssertLessThanOrEqual(user.count, RefinePrompt.maxSourceChars + 4000)
    }
}
