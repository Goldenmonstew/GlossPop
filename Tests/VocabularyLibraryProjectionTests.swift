import XCTest
@testable import GlossPop

@MainActor
final class VocabularyLibraryProjectionTests: XCTestCase {
    func testSearchCoversPronunciationDefinitionsExamplesSynonymsAndIdioms() {
        let entries = VocabularyDemo.makeStore(empty: false).entries

        XCTAssertEqual(matches(entries, "huiyi").map(\.term), ["会议"])
        XCTAssertEqual(matches(entries, "project meeting").map(\.term), ["会议"])
        XCTAssertEqual(matches(entries, "FORTUNÉ").map(\.term), ["serendipity"])
        XCTAssertEqual(matches(entries, "  FORTUNÉ \n").map(\.term), ["serendipity"])
        XCTAssertEqual(matches(entries, "call it quits").map(\.term), ["call it a day"])
        XCTAssertEqual(matches(entries, "停止某項活動").map(\.term), ["call it a day"])
        XCTAssertEqual(matches(entries, " \n\t "), entries)
    }

    func testLanguagePairFilterIsExactAndPreservesStoredOrder() {
        let entries = VocabularyDemo.makeStore(empty: false).entries
        let pair = VocabularyLanguagePair(
            sourceLanguage: "auto",
            targetLanguage: "zh-Hant"
        )

        let filtered = VocabularyLibraryProjection.filtered(
            entries,
            query: "",
            languagePair: pair
        )

        XCTAssertEqual(filtered.map(\.term), ["call it a day"])
        XCTAssertEqual(
            VocabularyLibraryProjection.filtered(
                entries,
                query: "",
                languagePair: nil
            ),
            entries
        )
    }

    func testSummaryPrefersAITranslationAndFallsBackToSystemBody() throws {
        let entries = VocabularyDemo.makeStore(empty: false).entries
        let serendipity = try XCTUnwrap(entries.first { $0.term == "serendipity" })
        let meeting = try XCTUnwrap(entries.first { $0.term == "会议" })
        var systemOnly = meeting
        systemOnly.aiEntry = nil

        XCTAssertEqual(
            VocabularyLibraryProjection.summary(for: serendipity),
            "机缘巧合；意外发现美好事物的运气"
        )
        XCTAssertEqual(
            VocabularyLibraryProjection.summary(for: systemOnly),
            "① （指集会） meeting"
        )
    }

    func testSelectionMovesToNextRowThenPreviousAtEnd() {
        let before = VocabularyDemo.makeStore(empty: false).entries
        let middle = before[1]
        let afterMiddle = before.filter { $0.id != middle.id }

        XCTAssertEqual(
            VocabularyLibraryProjection.nextSelection(
                before: before,
                deleting: middle.id,
                after: afterMiddle
            ),
            before[2].id
        )

        let last = before[2]
        let afterLast = before.filter { $0.id != last.id }
        XCTAssertEqual(
            VocabularyLibraryProjection.nextSelection(
                before: before,
                deleting: last.id,
                after: afterLast
            ),
            before[1].id
        )
        XCTAssertNil(
            VocabularyLibraryProjection.nextSelection(
                before: [last],
                deleting: last.id,
                after: []
            )
        )

        let current = before[0]
        XCTAssertEqual(
            VocabularyLibraryProjection.nextSelection(
                before: before,
                deleting: middle.id,
                after: afterMiddle,
                currentSelection: current.id
            ),
            current.id
        )
    }

    func testLanguageTrackDoesNotInventAnAutoDetectedLanguage() {
        XCTAssertEqual(
            VocabularyLibraryProjection.languageTrack(
                .init(sourceLanguage: "auto", targetLanguage: "zh-Hant")
            ),
            "AUTO → ZH-HANT"
        )
        XCTAssertEqual(
            VocabularyLibraryProjection.languageTrack(
                .init(sourceLanguage: "en", targetLanguage: "de")
            ),
            "EN → DE"
        )
    }

    private func matches(
        _ entries: [VocabularyEntry],
        _ query: String
    ) -> [VocabularyEntry] {
        VocabularyLibraryProjection.filtered(
            entries,
            query: query,
            languagePair: nil
        )
    }
}
