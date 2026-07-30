import Foundation
import XCTest
@testable import GlossPop

@MainActor
final class VocabularyStoreTests: XCTestCase {
    private enum TestPersistenceError: Error {
        case readFailed
        case writeFailed
        case moveFailed
    }

    func testCombinedEntryRoundTripsWithUnicodeAndSchemaVersion() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let date = Date(timeIntervalSince1970: 1_800_000_000.125)
        let store = VocabularyStore(
            fileURL: location.file,
            now: { date },
            makeID: { id }
        )

        let saved = try store.upsert(completeDraft(term: "机缘巧合"))

        XCTAssertEqual(saved.id, id)
        XCTAssertEqual(saved.createdAt, date)
        XCTAssertEqual(saved.origins, [.systemDictionary, .aiDictionary])
        XCTAssertEqual(saved.headword, "serendipity")
        XCTAssertEqual(saved.pronunciation, "/ˌserənˈdɪpɪti/")

        let data = try Data(contentsOf: location.file)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual((object["schemaVersion"] as? NSNumber)?.intValue, 1)

        let reloaded = VocabularyStore(fileURL: location.file)
        XCTAssertEqual(reloaded.loadState, .ready)
        XCTAssertEqual(reloaded.entries, [saved])
    }

    func testSameKeyPreservesIdentityAndMergesLateAIContent() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        var timestamp = Date(timeIntervalSince1970: 100)
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let store = VocabularyStore(
            fileURL: location.file,
            now: { timestamp },
            makeID: { id }
        )
        let pair = VocabularyLanguagePair(sourceLanguage: "EN", targetLanguage: "zh_Hans")
        let original = try store.upsert(
            VocabularyDraft(
                term: "  Lucky   break ",
                languagePair: pair,
                systemEntry: systemSnapshot,
                aiEntry: nil
            )
        )

        timestamp = Date(timeIntervalSince1970: 200)
        _ = try store.upsert(
            VocabularyDraft(
                term: "lucky break",
                languagePair: VocabularyLanguagePair(
                    sourceLanguage: "en",
                    targetLanguage: "zh-hans"
                ),
                systemEntry: nil,
                aiEntry: aiSnapshot
            )
        )

        let merged = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(merged.id, original.id)
        XCTAssertEqual(merged.createdAt, original.createdAt)
        XCTAssertEqual(merged.updatedAt, timestamp)
        XCTAssertEqual(merged.languagePair.sourceLanguage, "en")
        XCTAssertEqual(merged.languagePair.targetLanguage, "zh-Hans")
        XCTAssertEqual(merged.systemEntry, systemSnapshot)
        XCTAssertEqual(merged.aiEntry, aiSnapshot)
    }

    func testUpdatedEntryMovesToFront() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        var timestamp = Date(timeIntervalSince1970: 100)
        let store = VocabularyStore(fileURL: location.file, now: { timestamp })

        _ = try store.upsert(systemDraft(term: "first"))
        timestamp = Date(timeIntervalSince1970: 200)
        _ = try store.upsert(systemDraft(term: "second"))
        timestamp = Date(timeIntervalSince1970: 300)
        _ = try store.upsert(systemDraft(term: "FIRST"))

        XCTAssertEqual(store.entries.map(\.term), ["FIRST", "second"])
    }

    func testPersistedOrderSurvivesEqualTimestampsAndClockRollback() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        var timestamp = Date(timeIntervalSince1970: 200)
        let store = VocabularyStore(fileURL: location.file, now: { timestamp })

        _ = try store.upsert(systemDraft(term: "first"))
        _ = try store.upsert(systemDraft(term: "same-time"))
        timestamp = Date(timeIntervalSince1970: 100)
        _ = try store.upsert(systemDraft(term: "clock-rolled-back"))

        let expected = ["clock-rolled-back", "same-time", "first"]
        XCTAssertEqual(store.entries.map(\.term), expected)
        XCTAssertEqual(VocabularyStore(fileURL: location.file).entries.map(\.term), expected)
    }

    func testLanguagePairsRemainDistinct() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)

        _ = try store.upsert(systemDraft(term: "gift", source: "en", target: "de"))
        _ = try store.upsert(systemDraft(term: "gift", source: "en", target: "fr"))
        _ = try store.upsert(systemDraft(term: "gift", source: "de", target: "en"))

        XCTAssertEqual(store.count, 3)
        XCTAssertTrue(
            store.contains(
                term: "gift",
                languagePair: .init(sourceLanguage: "en", targetLanguage: "fr")
            )
        )
    }

    func testKeyFoldsCaseWidthWhitespaceAndCanonicalUnicodeButNotDiacritics() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)

        _ = try store.upsert(
            systemDraft(term: "  Ｒe\u{301}sume\u{301}  ", source: "EN_US", target: "ZH_HANS")
        )
        _ = try store.upsert(
            systemDraft(term: "résumé", source: "en-us", target: "zh-hans")
        )
        _ = try store.upsert(
            systemDraft(term: "resume", source: "en-us", target: "zh-hans")
        )
        _ = try store.upsert(systemDraft(term: "Good   Morning"))
        _ = try store.upsert(systemDraft(term: " good\nmorning "))

        XCTAssertEqual(store.count, 3)
        XCTAssertEqual(
            store.entries.first { $0.term == "resume" }?.languagePair.targetLanguage,
            "zh-Hans"
        )
        XCTAssertEqual(
            store.entries.filter { $0.term.localizedCaseInsensitiveContains("résumé") }.count,
            1
        )
        XCTAssertNotNil(
            store.entry(
                term: "RESUME",
                languagePair: .init(sourceLanguage: "en-us", targetLanguage: "zh-hans")
            )
        )
    }

    func testEmptySnapshotLayersAreDiscardedAndCannotCreateAIOnlyEntry() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let emptyAI = VocabularyAISnapshot(
            headword: "echo",
            pronunciation: "/echo/",
            senses: [
                VocabularySense(
                    partOfSpeech: "noun",
                    definition: " ",
                    translation: "\n",
                    register: "formal",
                    examples: [.init(source: " ", target: "\t")],
                    synonyms: [" "]
                ),
            ],
            idioms: [.init(phrase: "an empty phrase", meaning: " ")]
        )

        let saved = try store.upsert(
            VocabularyDraft(
                term: "kept",
                languagePair: .init(sourceLanguage: "en", targetLanguage: "zh-Hans"),
                systemEntry: systemSnapshot,
                aiEntry: emptyAI
            )
        )

        XCTAssertEqual(saved.origins, [.systemDictionary])
        XCTAssertNil(saved.aiEntry)
        XCTAssertThrowsError(
            try store.upsert(
                VocabularyDraft(
                    term: "not kept",
                    languagePair: .init(sourceLanguage: "en", targetLanguage: "zh-Hans"),
                    systemEntry: nil,
                    aiEntry: emptyAI
                )
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyStoreError, .emptyContent)
        }
        XCTAssertEqual(store.count, 1)
    }

    func testRemoveAndClearPersist() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let first = try store.upsert(systemDraft(term: "first"))
        _ = try store.upsert(systemDraft(term: "second"))

        XCTAssertTrue(try store.remove(id: first.id))
        XCTAssertFalse(try store.remove(id: UUID()))
        XCTAssertEqual(VocabularyStore(fileURL: location.file).entries.map(\.term), ["second"])

        try store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(VocabularyStore(fileURL: location.file).entries.isEmpty)
    }

    func testInvalidDraftDoesNotChangeMemoryOrDisk() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        _ = try store.upsert(systemDraft(term: "kept"))
        let originalEntries = store.entries
        let originalData = try Data(contentsOf: location.file)

        XCTAssertThrowsError(
            try store.upsert(
                VocabularyDraft(
                    term: " ",
                    languagePair: .init(sourceLanguage: "en", targetLanguage: "zh-Hans"),
                    systemEntry: systemSnapshot,
                    aiEntry: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyStoreError, .emptyTerm)
        }
        XCTAssertThrowsError(
            try store.upsert(
                VocabularyDraft(
                    term: "empty",
                    languagePair: .init(sourceLanguage: "en", targetLanguage: "zh-Hans"),
                    systemEntry: nil,
                    aiEntry: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? VocabularyStoreError, .emptyContent)
        }

        XCTAssertEqual(store.entries, originalEntries)
        XCTAssertEqual(try Data(contentsOf: location.file), originalData)
    }

    func testWriteFailureKeepsMemoryAndExistingFileUnchanged() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let initialStore = VocabularyStore(fileURL: location.file)
        _ = try initialStore.upsert(systemDraft(term: "kept"))
        let originalData = try Data(contentsOf: location.file)

        let failingStore = VocabularyStore(
            fileURL: location.file,
            writeData: { _, _ in throw TestPersistenceError.writeFailed }
        )
        let originalEntries = failingStore.entries

        XCTAssertThrowsError(try failingStore.upsert(systemDraft(term: "not saved")))
        XCTAssertEqual(failingStore.entries, originalEntries)
        XCTAssertEqual(try Data(contentsOf: location.file), originalData)
    }

    func testReadFailureBlocksWritesAndPreservesOriginalFile() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let originalData = Data(#"{"schemaVersion":1,"entries":[]}"#.utf8)
        try originalData.write(to: location.file)

        let store = VocabularyStore(
            fileURL: location.file,
            readData: { _ in throw TestPersistenceError.readFailed }
        )

        XCTAssertEqual(store.loadState, .blocked(.unreadable))
        XCTAssertThrowsError(try store.upsert(systemDraft(term: "blocked"))) { error in
            XCTAssertEqual(error as? VocabularyStoreError, .blocked(.unreadable))
        }
        XCTAssertEqual(try Data(contentsOf: location.file), originalData)
    }

    func testCorruptFileIsQuarantinedByteForByteAndStoreCanContinue() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let corruptData = Data([0x00, 0xFF, 0x7B, 0x01])
        try corruptData.write(to: location.file)
        let backupID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!

        let store = VocabularyStore(fileURL: location.file, makeID: { backupID })
        let backupURL: URL
        switch store.loadState {
        case let .recoveredCorruptFile(url):
            backupURL = url
        default:
            return XCTFail("Expected corrupt-file recovery, got \(store.loadState)")
        }

        XCTAssertEqual(
            backupURL.lastPathComponent,
            "vocabulary-v1.corrupt-pending-\(backupID.uuidString).json"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.file.path))
        XCTAssertEqual(try Data(contentsOf: backupURL), corruptData)
        XCTAssertTrue(store.entries.isEmpty)

        _ = try store.upsert(systemDraft(term: "fresh"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.file.path))
        XCTAssertEqual(store.count, 1)
        let reloaded = VocabularyStore(fileURL: location.file)
        XCTAssertEqual(reloaded.entries.map(\.term), ["fresh"])
        guard case let .recoveredCorruptFile(reloadedBackupURL) = reloaded.loadState else {
            return XCTFail("Expected persisted recovery notice, got \(reloaded.loadState)")
        }
        XCTAssertEqual(
            reloadedBackupURL.resolvingSymlinksInPath(),
            backupURL.resolvingSymlinksInPath()
        )

        try reloaded.acknowledgeRecovery()
        XCTAssertEqual(reloaded.loadState, .ready)
        let keptURL = location.directory.appendingPathComponent(
            "vocabulary-v1.corrupt-kept-\(backupID.uuidString).json"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(try Data(contentsOf: keptURL), corruptData)
        XCTAssertEqual(VocabularyStore(fileURL: location.file).loadState, .ready)
    }

    func testAcknowledgingAnExternallyDeletedRecoveryBackupSucceeds() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try Data([0x00, 0xFF]).write(to: location.file)
        let store = VocabularyStore(fileURL: location.file)
        guard case let .recoveredCorruptFile(backupURL) = store.loadState else {
            return XCTFail("Expected corrupt-file recovery, got \(store.loadState)")
        }

        try FileManager.default.removeItem(at: backupURL)
        try store.acknowledgeRecovery()

        XCTAssertEqual(store.loadState, .ready)
    }

    func testClearKeepsPendingRecoveryBackupVisibleAcrossRestart() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let corruptData = Data([0x7B, 0xFF, 0x7D])
        try corruptData.write(to: location.file)
        let store = VocabularyStore(fileURL: location.file)
        guard case let .recoveredCorruptFile(backupURL) = store.loadState else {
            return XCTFail("Expected corrupt-file recovery, got \(store.loadState)")
        }
        _ = try store.upsert(systemDraft(term: "fresh"))

        try store.clear()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: backupURL), corruptData)
        let reloaded = VocabularyStore(fileURL: location.file)
        XCTAssertTrue(reloaded.entries.isEmpty)
        guard case let .recoveredCorruptFile(reloadedURL) = reloaded.loadState else {
            return XCTFail("Expected persisted recovery notice, got \(reloaded.loadState)")
        }
        XCTAssertEqual(
            reloadedURL.resolvingSymlinksInPath(),
            backupURL.resolvingSymlinksInPath()
        )
    }

    func testAcknowledgementFailureKeepsPendingRecoveryStateAndBytes() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let backupURL = location.directory.appendingPathComponent(
            "vocabulary-v1.corrupt-pending-AAAAAAAA-0000-0000-0000-000000000001.json"
        )
        let backupData = Data([0x01, 0x02, 0x03])
        try backupData.write(to: backupURL)
        let store = VocabularyStore(
            fileURL: location.file,
            moveItem: { _, _ in throw TestPersistenceError.moveFailed }
        )

        XCTAssertThrowsError(try store.acknowledgeRecovery())

        guard case let .recoveredCorruptFile(reportedURL) = store.loadState else {
            return XCTFail("Expected recovery state, got \(store.loadState)")
        }
        XCTAssertEqual(
            reportedURL.resolvingSymlinksInPath(),
            backupURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(try Data(contentsOf: backupURL), backupData)
    }

    func testFailedCorruptFileRecoveryBlocksEveryMutationAndPreservesBytes() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let corruptData = Data([0x7B, 0xFF, 0x7D])
        try corruptData.write(to: location.file)

        let store = VocabularyStore(
            fileURL: location.file,
            moveItem: { _, _ in throw TestPersistenceError.moveFailed }
        )

        XCTAssertEqual(store.loadState, .blocked(.recoveryFailed))
        XCTAssertThrowsError(try store.upsert(systemDraft(term: "blocked")))
        XCTAssertThrowsError(try store.clear())
        XCTAssertThrowsError(
            try store.remove(
                term: "anything",
                languagePair: .init(sourceLanguage: "en", targetLanguage: "zh-Hans")
            )
        )
        XCTAssertEqual(try Data(contentsOf: location.file), corruptData)
    }

    func testFutureVersionIsPreservedAndBlocksMutations() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let futureData = Data(#"{"schemaVersion":2,"entries":[]}"#.utf8)
        try futureData.write(to: location.file)

        let store = VocabularyStore(fileURL: location.file)

        XCTAssertEqual(store.loadState, .blocked(.unsupportedVersion(2)))
        XCTAssertThrowsError(try store.upsert(systemDraft(term: "blocked"))) { error in
            XCTAssertEqual(
                error as? VocabularyStoreError,
                .blocked(.unsupportedVersion(2))
            )
        }
        XCTAssertEqual(try Data(contentsOf: location.file), futureData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.file.path))
        let directoryContents = try FileManager.default.contentsOfDirectory(
            at: location.directory,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(directoryContents.contains { $0.lastPathComponent.contains(".corrupt-") })
    }

    private var systemSnapshot: VocabularySystemSnapshot {
        VocabularySystemSnapshot(
            headword: "serendipity",
            pronunciation: "/ˌserənˈdɪpɪti/",
            body: "noun 机缘巧合；意外发现珍奇事物的本领",
            hasCJK: true
        )
    }

    private var aiSnapshot: VocabularyAISnapshot {
        VocabularyAISnapshot(
            headword: "serendipity",
            pronunciation: "/ˌserənˈdɪpɪti/",
            senses: [
                VocabularySense(
                    partOfSpeech: "noun",
                    definition: "The occurrence of a fortunate discovery by chance.",
                    translation: "机缘巧合",
                    register: "neutral",
                    examples: [
                        VocabularyExample(
                            source: "The discovery was pure serendipity.",
                            target: "这次发现纯属机缘巧合。"
                        ),
                    ],
                    synonyms: ["chance", "fortune"]
                ),
            ],
            idioms: [
                VocabularyIdiom(
                    phrase: "a stroke of serendipity",
                    meaning: "一次幸运的巧合"
                ),
            ]
        )
    }

    private func completeDraft(term: String) -> VocabularyDraft {
        VocabularyDraft(
            term: term,
            languagePair: .init(sourceLanguage: "en", targetLanguage: "zh-Hans"),
            systemEntry: systemSnapshot,
            aiEntry: aiSnapshot
        )
    }

    private func systemDraft(
        term: String,
        source: String = "en",
        target: String = "zh-Hans"
    ) -> VocabularyDraft {
        VocabularyDraft(
            term: term,
            languagePair: .init(sourceLanguage: source, targetLanguage: target),
            systemEntry: systemSnapshot,
            aiEntry: nil
        )
    }

    private func makeLocation() throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlossPopVocabularyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return (directory, directory.appendingPathComponent("vocabulary-v1.json"))
    }
}
