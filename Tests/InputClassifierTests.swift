import XCTest
@testable import GlossPop

final class InputClassifierTests: XCTestCase {
    func testSingleWordIsWord() {
        XCTAssertEqual(InputClassifier.classify("serendipity").kind, .word)
    }

    func testShortNounPhraseIsPhrase() {
        XCTAssertEqual(InputClassifier.classify("good morning").kind, .phrase)
    }

    func testSentenceWithPunctuationIsSentence() {
        XCTAssertEqual(InputClassifier.classify("The quick brown fox jumps over the lazy dog.").kind, .sentence)
    }

    func testClauseWithVerbIsSentence() {
        XCTAssertEqual(InputClassifier.classify("Although it was raining she walked").kind, .sentence)
    }

    func testSourceDetected() {
        XCTAssertEqual(InputClassifier.classify("The quick brown fox jumps.").source.languageCode?.identifier, "en")
    }

    func testCJKFullWidthQuestionIsSentence() {
        XCTAssertEqual(InputClassifier.classify("你今天过得怎么样？").kind, .sentence)
    }
}
