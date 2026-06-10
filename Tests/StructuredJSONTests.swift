import XCTest
@testable import GlossPop

final class StructuredJSONTests: XCTestCase {
    func testExtractObjectFromFencedJSON() {
        let raw = "```json\n{\"a\":1}\n```"
        XCTAssertNotNil(StructuredJSON.object(from: raw))
        XCTAssertNil(StructuredJSON.object(from: "no json here"))
    }

    func testExtractFirstBalancedObjectIgnoringBraceyProse() {
        // Leading prose with a stray brace + a balanced answer object → must return the answer, not span both.
        let raw = "Here is the result (note: {x}) →\n{\"headword\":\"ok\",\"senses\":[]}\ntrailing {junk"
        let obj = StructuredJSON.object(from: raw)
        XCTAssertEqual(obj?["headword"] as? String, "ok")
    }

    func testBraceInsideStringDoesNotEndObject() {
        let raw = #"{"definition":"a } brace in a string","headword":"x"}"#
        XCTAssertEqual(StructuredJSON.object(from: raw)?["headword"] as? String, "x")
    }

    func testDictionaryParsing() {
        let json = """
        {"headword":"serendipity","pronunciation":"/x/","senses":[{"partOfSpeech":"noun","translation":"机缘",
        "definition":"d","examples":[{"source":"a","target":"b"}],"synonyms":["luck","fortune"],"register":"neutral"}],
        "idioms":[{"phrase":"by serendipity","meaning":"偶然"}]}
        """
        let obj = StructuredJSON.object(from: json)!
        let entry = StructuredJSON.dictionary(from: obj)
        XCTAssertEqual(entry.headword, "serendipity")
        XCTAssertEqual(entry.senses.count, 1)
        XCTAssertEqual(entry.senses.first?.translation, "机缘")
        XCTAssertEqual(entry.senses.first?.examples.count, 1)
        XCTAssertEqual(entry.senses.first?.synonyms, ["luck", "fortune"])
        XCTAssertEqual(entry.idioms.count, 1)
        XCTAssertFalse(entry.isEmpty)
    }

    func testSentenceParsing() {
        let json = """
        {"refinedTranslation":"译","literalTranslation":"直","syntax":{"subject":"she","predicate":"walked",
        "objects":["station"],"clauses":[{"text":"she walked","role":"主句"}],
        "grammarPoints":[{"point":"过去式","explanation":"e"}],"tokenGloss":[{"surface":"she","lemma":"she","pos":"pron","gloss":"她"}]},
        "notes":["n1"]}
        """
        let obj = StructuredJSON.object(from: json)!
        let a = StructuredJSON.sentence(from: obj)
        XCTAssertEqual(a.refinedTranslation, "译")
        XCTAssertEqual(a.syntax.subject, "she")
        XCTAssertEqual(a.syntax.objects, ["station"])
        XCTAssertEqual(a.syntax.grammarPoints.count, 1)
        XCTAssertEqual(a.syntax.tokenGloss.first?.gloss, "她")
        XCTAssertFalse(a.isEmpty)
    }

    func testMissingKeysAreSafe() {
        let entry = StructuredJSON.dictionary(from: ["headword": "x"])
        XCTAssertEqual(entry.headword, "x")
        XCTAssertTrue(entry.senses.isEmpty)
    }
}
