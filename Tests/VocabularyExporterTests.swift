import Foundation
import XCTest
@testable import GlossPop

final class VocabularyExporterTests: XCTestCase {
    func testFormatExtensionsAreStable() {
        XCTAssertEqual(VocabularyExportFormat.csv.filenameExtension, "csv")
        XCTAssertEqual(VocabularyExportFormat.ankiTSV.filenameExtension, "txt")
    }

    func testCSVPreservesEntryOrderLayersUnicodeAndEmptyValues() throws {
        let combined = makeEntry(
            id: "00000000-0000-0000-0000-000000000001",
            term: "会議",
            source: "ja",
            target: "zh-Hant",
            system: .init(
                headword: "会議",
                pronunciation: "かいぎ",
                body: "noun meeting",
                hasCJK: true
            ),
            ai: .init(
                headword: "会議",
                pronunciation: "かいぎ",
                senses: [
                    .init(
                        partOfSpeech: "noun",
                        definition: "a formal discussion",
                        translation: "會議",
                        register: "",
                        examples: [
                            .init(source: "会議を始めます。", target: "開始會議。"),
                        ],
                        synonyms: ["集会"]
                    ),
                ],
                idioms: []
            )
        )
        let systemOnly = makeEntry(
            id: "00000000-0000-0000-0000-000000000002",
            term: "alpha",
            source: "en",
            target: "de",
            system: .init(
                headword: "alpha",
                pronunciation: "",
                body: "the first letter",
                hasCJK: false
            )
        )
        let aiOnly = makeEntry(
            id: "00000000-0000-0000-0000-000000000003",
            term: "empty optionals",
            source: "en",
            target: "fr",
            ai: .init(
                headword: "",
                pronunciation: "",
                senses: [
                    .init(
                        partOfSpeech: "",
                        definition: "",
                        translation: "valeur",
                        register: "",
                        examples: [],
                        synonyms: []
                    ),
                ],
                idioms: []
            )
        )

        let data = try VocabularyExporter.data(
            for: .csv,
            entries: [combined, systemOnly, aiOnly]
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let rows = try parseCSV(text)

        XCTAssertTrue(text.hasSuffix("\r\n"))
        XCTAssertEqual(rows.count, 4)
        guard rows.count == 4 else { return }
        XCTAssertEqual(rows[0].count, 11)
        XCTAssertEqual(rows.dropFirst().map { $0[0] }, ["会議", "alpha", "empty optionals"])
        XCTAssertEqual(rows[1][5], "noun meeting")
        XCTAssertEqual(rows[1][8], """
        Sense 1
        Part of speech: noun
        Definition: a formal discussion
        Translation: 會議
        Examples:
        - 会議を始めます。 — 開始會議。
        Synonyms: 集会
        """)
        XCTAssertEqual(rows[2][6], "")
        XCTAssertEqual(rows[2][8], "")
        XCTAssertEqual(rows[3][3], "")
        XCTAssertEqual(rows[3][5], "")
        XCTAssertEqual(rows[1][9], "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(rows[1][10], "1970-01-01T00:01:00.000Z")
    }

    func testCSVQuotesDelimitersAndNeutralisesFormulaInjection() throws {
        let entry = makeEntry(
            term: "  =HYPERLINK(\"https://example.com\", \"click\")",
            source: "+cmd",
            target: "@target",
            system: .init(
                headword: "-danger",
                pronunciation: "comma, quote \" and\ttab",
                body: "first\r\nsecond\nthird\rfourth",
                hasCJK: false
            )
        )

        let data = try VocabularyExporter.data(for: .csv, entries: [entry])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let rows = try parseCSV(text)

        XCTAssertEqual(rows.count, 2)
        guard rows.count == 2 else { return }
        XCTAssertEqual(
            rows[1][0],
            "'  =HYPERLINK(\"https://example.com\", \"click\")"
        )
        XCTAssertEqual(rows[1][1], "'+cmd")
        XCTAssertEqual(rows[1][2], "'@target")
        XCTAssertEqual(rows[1][3], "'-danger")
        XCTAssertEqual(rows[1][4], "comma, quote \" and\ttab")
        XCTAssertEqual(rows[1][5], "first\r\nsecond\nthird\rfourth")
        XCTAssertTrue(
            text.contains(
                "\"'  =HYPERLINK(\"\"https://example.com\"\", \"\"click\"\")\""
            )
        )
    }

    func testAnkiTSVUsesSingleLineEscapedHTMLAndStableTags() throws {
        let entry = makeEntry(
            term: "=word\t<unsafe>",
            source: "EN",
            target: "zh_Hant",
            system: .init(
                headword: "=word\t<unsafe>",
                pronunciation: "\"quoted\" & voiced",
                body: "first\r\nsecond\nthird\tindented",
                hasCJK: false
            ),
            ai: .init(
                headword: "=word\t<unsafe>",
                pronunciation: "\"quoted\" & voiced",
                senses: [
                    .init(
                        partOfSpeech: "noun",
                        definition: "<script>alert(\"x\")</script>",
                        translation: "含義",
                        register: "formal",
                        examples: [
                            .init(source: "one\tpart", target: "line 1\nline 2"),
                        ],
                        synonyms: ["A&B", "\"quoted\""]
                    ),
                ],
                idioms: [
                    .init(phrase: "x < y", meaning: "safe & sound"),
                ]
            )
        )

        let data = try VocabularyExporter.data(for: .ankiTSV, entries: [entry])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(lines[0], "#separator:tab")
        XCTAssertEqual(lines[1], "#html:true")
        XCTAssertEqual(lines[2], "#columns:Front\tBack\tTags")
        XCTAssertEqual(lines[3], "#tags column:3")
        XCTAssertEqual(lines.count, 6)

        let fields = lines[4].split(separator: "\t", omittingEmptySubsequences: false)
        XCTAssertEqual(fields.count, 3)
        XCTAssertEqual(
            fields[0],
            """
            <span dir="auto">=word&emsp;&lt;unsafe&gt;</span><br><small>EN → zh_Hant</small>
            """
        )
        XCTAssertTrue(fields[1].contains("&quot;quoted&quot; &amp; voiced"))
        XCTAssertTrue(fields[1].contains("first<br>second<br>third&emsp;indented"))
        XCTAssertTrue(fields[1].contains("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"))
        XCTAssertTrue(fields[1].contains("one&emsp;part — line 1<br>line 2"))
        XCTAssertTrue(fields[1].contains("x &lt; y — safe &amp; sound"))
        XCTAssertEqual(
            fields[2],
            "glosspop source-en target-zh-hant system-dictionary ai-dictionary"
        )
        XCTAssertFalse(String(lines[4]).contains("\r"))
        XCTAssertFalse(String(lines[4]).hasPrefix("'"))
    }

    func testAnkiFrontCannotBecomeACommentAndDistinguishesLanguagePairs() throws {
        let german = makeEntry(
            id: "00000000-0000-0000-0000-000000000001",
            term: "#tag",
            source: "en",
            target: "de",
            system: .init(
                headword: "#tag",
                pronunciation: "",
                body: "German meaning",
                hasCJK: false
            )
        )
        let french = makeEntry(
            id: "00000000-0000-0000-0000-000000000002",
            term: "#tag",
            source: "en",
            target: "fr",
            system: .init(
                headword: "#tag",
                pronunciation: "",
                body: "French meaning",
                hasCJK: false
            )
        )

        let data = try VocabularyExporter.data(
            for: .ankiTSV,
            entries: [german, french]
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let rows = text.split(separator: "\n").dropFirst(4)
        XCTAssertEqual(rows.count, 2)
        guard rows.count == 2 else { return }

        let fronts = rows.map {
            String($0.split(separator: "\t", maxSplits: 1)[0])
        }
        XCTAssertTrue(fronts.allSatisfy { $0.hasPrefix("<span") })
        XCTAssertTrue(fronts.allSatisfy { $0.contains("#tag") })
        XCTAssertNotEqual(fronts[0], fronts[1])
        XCTAssertTrue(fronts[0].contains("en → de"))
        XCTAssertTrue(fronts[1].contains("en → fr"))
    }

    func testAnkiBackIsNotEmptyForHeadwordOnlySystemEntry() throws {
        let entry = makeEntry(
            term: "alpha",
            source: "en",
            target: "de",
            system: .init(
                headword: "alpha",
                pronunciation: "",
                body: "",
                hasCJK: false
            )
        )

        let data = try VocabularyExporter.data(for: .ankiTSV, entries: [entry])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let row = try XCTUnwrap(text.split(separator: "\n").dropFirst(4).first)
        let fields = row.split(separator: "\t", omittingEmptySubsequences: false)

        XCTAssertEqual(fields.count, 3)
        XCTAssertEqual(fields[1], "<b>Headword</b><br>alpha")
    }

    func testEmptyExportsContainOnlyTheirSchema() throws {
        let csv = try XCTUnwrap(
            String(
                data: VocabularyExporter.data(for: .csv, entries: []),
                encoding: .utf8
            )
        )
        let csvRows = try parseCSV(csv)
        XCTAssertEqual(csvRows.count, 1)
        XCTAssertEqual(csvRows[0].count, 11)

        let anki = try XCTUnwrap(
            String(
                data: VocabularyExporter.data(for: .ankiTSV, entries: []),
                encoding: .utf8
            )
        )
        XCTAssertEqual(
            anki,
            """
            #separator:tab
            #html:true
            #columns:Front\tBack\tTags
            #tags column:3

            """
        )
    }

    func testFileWriterAtomicallyWritesAndReadsBackExactBytes() throws {
        let destination = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: destination) }
        let data = Data("会議,\"quoted\"\r\n".utf8)

        try VocabularyExportFileWriter().writeAndVerify(data, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), data)
    }

    func testFileWriterReportsReadBackMismatch() {
        let expected = Data("expected".utf8)
        let writer = VocabularyExportFileWriter(
            writeData: { _, _ in },
            readData: { _ in Data("different".utf8) }
        )

        XCTAssertThrowsError(
            try writer.writeAndVerify(expected, to: temporaryFileURL())
        ) { error in
            XCTAssertEqual(
                error as? VocabularyExportFileError,
                .verificationFailed
            )
        }
    }

    func testWriteFailureDoesNotReplaceAnExistingDestination() throws {
        let destination = temporaryFileURL()
        let original = Data("keep me".utf8)
        try original.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let writer = VocabularyExportFileWriter(
            writeData: { _, _ in throw CocoaError(.fileWriteNoPermission) },
            readData: { _ in
                XCTFail("A failed write must not be verified.")
                return Data()
            }
        )

        XCTAssertThrowsError(
            try writer.writeAndVerify(Data("replacement".utf8), to: destination)
        )
        XCTAssertEqual(try Data(contentsOf: destination), original)
    }

    private func makeEntry(
        id: String = "00000000-0000-0000-0000-000000000000",
        term: String,
        source: String,
        target: String,
        system: VocabularySystemSnapshot? = nil,
        ai: VocabularyAISnapshot? = nil
    ) -> VocabularyEntry {
        VocabularyEntry(
            id: UUID(uuidString: id)!,
            term: term,
            languagePair: .init(
                sourceLanguage: source,
                targetLanguage: target
            ),
            systemEntry: system,
            aiEntry: ai,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 60)
        )
    }

    private func parseCSV(_ value: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]
            let nextIndex = value.index(after: index)

            if character == "\"" {
                if inQuotes,
                   nextIndex < value.endIndex,
                   value[nextIndex] == "\"" {
                    field.append("\"")
                    index = value.index(after: nextIndex)
                    continue
                }
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if character == "\r", !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                if nextIndex < value.endIndex, value[nextIndex] == "\n" {
                    index = value.index(after: nextIndex)
                    continue
                }
            } else if character == "\r\n", !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if character == "\n", !inQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = nextIndex
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        guard !inQuotes else { throw CSVTestError.unclosedQuote }
        return rows
    }

    private enum CSVTestError: Error {
        case unclosedQuote
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GlossPopExportTests-\(UUID().uuidString)")
    }
}
