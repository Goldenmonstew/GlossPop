import AppKit
import XCTest
@testable import GlossPop

@MainActor
final class PanelResultActionsTests: XCTestCase {
    func testWordPayloadKeepsSystemCopyStableWhenAIContentArrives() throws {
        let context = makeContext(kind: .word)
        let system = SystemDictionary.Entry(
            headword: "serendipity",
            pronunciation: "/ˌserənˈdɪpɪti/",
            body: "noun 机缘巧合",
            hasCJK: true
        )

        let systemOnly = try XCTUnwrap(
            PanelResultActionBuilder.word(
                context: context,
                systemEntry: system,
                aiEntry: nil
            )
        )
        let combined = try XCTUnwrap(
            PanelResultActionBuilder.word(
                context: context,
                systemEntry: system,
                aiEntry: dictionaryEntry
            )
        )

        XCTAssertEqual(systemOnly.copyText, system.body)
        XCTAssertEqual(combined.copyText, system.body)
        XCTAssertNotNil(combined.vocabularyDraft?.systemEntry)
        XCTAssertNotNil(combined.vocabularyDraft?.aiEntry)
        XCTAssertEqual(combined.vocabularyDraft?.languagePair.targetLanguage, "zh-Hans")
    }

    func testAIOnlyPayloadUsesFirstTranslationThenDefinition() throws {
        let context = makeContext(kind: .phrase)
        var translated = dictionaryEntry
        translated.senses[0].translation = "机缘巧合"
        translated.senses[0].definition = "A fortunate accidental discovery."
        let translationPayload = try XCTUnwrap(
            PanelResultActionBuilder.word(
                context: context,
                systemEntry: nil,
                aiEntry: translated
            )
        )

        translated.senses[0].translation = " "
        let definitionPayload = try XCTUnwrap(
            PanelResultActionBuilder.word(
                context: context,
                systemEntry: nil,
                aiEntry: translated
            )
        )

        XCTAssertEqual(translationPayload.copyText, "机缘巧合")
        XCTAssertEqual(definitionPayload.copyText, "A fortunate accidental discovery.")
    }

    func testPlainPayloadOnlyOffersVocabularyForWordsAndPhrases() throws {
        let sentence = try XCTUnwrap(
            PanelResultActionBuilder.plain(
                context: makeContext(kind: .sentence),
                text: "这是一段译文。",
                allowsVocabulary: true
            )
        )
        let word = try XCTUnwrap(
            PanelResultActionBuilder.plain(
                context: makeContext(kind: .word),
                text: "机缘巧合",
                allowsVocabulary: true
            )
        )
        let interruptedWord = try XCTUnwrap(
            PanelResultActionBuilder.plain(
                context: makeContext(kind: .word),
                text: "partial",
                allowsVocabulary: false
            )
        )

        XCTAssertNil(sentence.vocabularyDraft)
        XCTAssertNotNil(word.vocabularyDraft)
        XCTAssertNil(interruptedWord.vocabularyDraft)
    }

    func testAutomaticEnrichmentOnlyFillsMissingLayers() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let context = makeContext(kind: .word)
        let system = SystemDictionary.Entry(
            headword: "serendipity",
            pronunciation: "",
            body: "noun 机缘巧合",
            hasCJK: true
        )
        let systemDraft = try XCTUnwrap(
            PanelResultActionBuilder.word(
                context: context,
                systemEntry: system,
                aiEntry: nil
            )?.vocabularyDraft
        )
        let combinedDraft = try XCTUnwrap(
            PanelResultActionBuilder.word(
                context: context,
                systemEntry: system,
                aiEntry: dictionaryEntry
            )?.vocabularyDraft
        )
        var replacementAI = dictionaryEntry
        replacementAI.senses[0].translation = "replacement that must not overwrite"
        let replacementCombinedDraft = try XCTUnwrap(
            PanelResultActionBuilder.word(
                context: context,
                systemEntry: system,
                aiEntry: replacementAI
            )?.vocabularyDraft
        )
        let plainDraft = try XCTUnwrap(
            PanelResultActionBuilder.plain(
                context: context,
                text: "single fallback translation",
                allowsVocabulary: true
            )?.vocabularyDraft
        )
        let date = Date(timeIntervalSince1970: 100)
        let systemOnly = VocabularyEntry(
            id: UUID(),
            term: context.source,
            languagePair: systemDraft.languagePair,
            systemEntry: systemDraft.systemEntry,
            aiEntry: nil,
            createdAt: date,
            updatedAt: date
        )
        let richEntry = VocabularyEntry(
            id: UUID(),
            term: context.source,
            languagePair: combinedDraft.languagePair,
            systemEntry: combinedDraft.systemEntry,
            aiEntry: combinedDraft.aiEntry,
            createdAt: date,
            updatedAt: date
        )

        let aiDelta = try XCTUnwrap(
            PanelResultActionBuilder.enrichmentDraft(
                existing: systemOnly,
                with: combinedDraft
            )
        )
        XCTAssertNil(aiDelta.systemEntry)
        XCTAssertEqual(aiDelta.aiEntry, combinedDraft.aiEntry)
        XCTAssertNil(
            PanelResultActionBuilder.enrichmentDraft(
                existing: richEntry,
                with: plainDraft
            )
        )
        XCTAssertNil(
            PanelResultActionBuilder.enrichmentDraft(
                existing: richEntry,
                with: combinedDraft
            )
        )

        let aiOnlyDraft = VocabularyDraft(
            term: combinedDraft.term,
            languagePair: combinedDraft.languagePair,
            systemEntry: nil,
            aiEntry: combinedDraft.aiEntry
        )
        let savedAIOnly = try store.upsert(aiOnlyDraft)
        let systemDelta = try XCTUnwrap(
            PanelResultActionBuilder.enrichmentDraft(
                existing: savedAIOnly,
                with: replacementCombinedDraft
            )
        )
        XCTAssertEqual(systemDelta.systemEntry, replacementCombinedDraft.systemEntry)
        XCTAssertNil(systemDelta.aiEntry)

        _ = try store.upsert(systemDelta)
        let enriched = try XCTUnwrap(
            store.entry(
                term: combinedDraft.term,
                languagePair: combinedDraft.languagePair
            )
        )
        XCTAssertEqual(enriched.systemEntry, replacementCombinedDraft.systemEntry)
        XCTAssertEqual(enriched.aiEntry, combinedDraft.aiEntry)
    }

    func testBeginningNewCardClearsEveryResultAction() {
        let model = PanelModel()
        let oldContext = makeContext(kind: .word)
        model.beginCard(context: oldContext)
        model.copyText = "old result"
        model.vocabularyDraft = PanelResultActionBuilder.plain(
            context: oldContext,
            text: "old result",
            allowsVocabulary: true
        )?.vocabularyDraft
        model.action = .aiDictionary
        model.isVocabularySaved = true
        model.copyConfirmed = true
        model.setResultActionError("old action error", kind: .copy)

        let newContext = makeContext(kind: .sentence)
        model.beginCard(context: newContext)

        XCTAssertEqual(model.context, newContext)
        XCTAssertNil(model.copyText)
        XCTAssertNil(model.vocabularyDraft)
        XCTAssertEqual(model.action, .none)
        XCTAssertFalse(model.isVocabularySaved)
        XCTAssertFalse(model.copyConfirmed)
        XCTAssertNil(model.resultActionError)
    }

    func testSuccessfulResultActionClearsOnlyItsTransientError() {
        let model = PanelModel()
        model.subtitle = "System dictionary · offline"
        model.essentialSubtitle = true
        model.setResultActionError("Copy failed", kind: .copy)

        let firstCopyGeneration = model.applyResultActionOutcome(.copied)

        XCTAssertNil(model.resultActionError)
        XCTAssertTrue(model.copyConfirmed)
        XCTAssertEqual(model.subtitle, "System dictionary · offline")
        XCTAssertTrue(model.essentialSubtitle)

        model.setResultActionError("Save failed", kind: .vocabulary)
        let secondCopyGeneration = model.applyResultActionOutcome(.copied)
        XCTAssertEqual(model.resultActionError?.message, "Save failed")
        XCTAssertGreaterThan(secondCopyGeneration, firstCopyGeneration)

        model.applyResultActionOutcome(.saved(true))

        XCTAssertNil(model.resultActionError)
        XCTAssertTrue(model.isVocabularySaved)
        XCTAssertEqual(model.subtitle, "System dictionary · offline")
        XCTAssertTrue(model.essentialSubtitle)

        model.setResultActionError("Still relevant", kind: .enrichment)
        model.applyResultActionOutcome(.ignored)
        XCTAssertEqual(model.resultActionError?.message, "Still relevant")
        model.applyResultActionOutcome(.saved(false))
        XCTAssertNil(model.resultActionError)
    }

    func testCopyFailureInvalidatesEarlierSuccessFeedback() {
        let model = PanelModel()
        let successGeneration = model.applyResultActionOutcome(.copied)
        XCTAssertTrue(model.copyConfirmed)

        model.setResultActionError("Copy failed", kind: .copy)

        XCTAssertFalse(model.copyConfirmed)
        XCTAssertGreaterThan(model.copyFeedbackGeneration, successGeneration)
    }

    func testStaleEventChangesNeitherPasteboardNorVocabulary() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("sentinel", forType: .string)
        let context = makeContext(kind: .word)
        let draft = try XCTUnwrap(
            PanelResultActionBuilder.plain(
                context: context,
                text: "机缘巧合",
                allowsVocabulary: true
            )?.vocabularyDraft
        )

        let copyOutcome = try PanelResultActionPerformer.perform(
            .copy(cardID: context.cardID),
            currentCardID: UUID(),
            currentCopyText: "should not copy",
            currentVocabularyDraft: draft,
            vocabularyStore: store,
            pasteboard: pasteboard
        )
        let saveOutcome = try PanelResultActionPerformer.perform(
            .setSaved(cardID: context.cardID, saved: true),
            currentCardID: UUID(),
            currentCopyText: "should not copy",
            currentVocabularyDraft: draft,
            vocabularyStore: store,
            pasteboard: pasteboard
        )

        XCTAssertEqual(copyOutcome, .ignored)
        XCTAssertEqual(saveOutcome, .ignored)
        XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testSameCardIntentUsesLatestCopyTextAndVocabularyDraft() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let pasteboard = makePasteboard()
        let context = makeContext(kind: .word)
        let system = SystemDictionary.Entry(
            headword: "serendipity",
            pronunciation: "",
            body: "noun 机缘巧合",
            hasCJK: true
        )
        let latestDraft = try XCTUnwrap(
            PanelResultActionBuilder.word(
                context: context,
                systemEntry: system,
                aiEntry: dictionaryEntry
            )?.vocabularyDraft
        )

        let copyOutcome = try PanelResultActionPerformer.perform(
            .copy(cardID: context.cardID),
            currentCardID: context.cardID,
            currentCopyText: "latest complete result",
            currentVocabularyDraft: latestDraft,
            vocabularyStore: store,
            pasteboard: pasteboard
        )
        let saveOutcome = try PanelResultActionPerformer.perform(
            .setSaved(cardID: context.cardID, saved: true),
            currentCardID: context.cardID,
            currentCopyText: "latest complete result",
            currentVocabularyDraft: latestDraft,
            vocabularyStore: store,
            pasteboard: pasteboard
        )

        XCTAssertEqual(copyOutcome, .copied)
        XCTAssertEqual(pasteboard.string(forType: .string), "latest complete result")
        XCTAssertEqual(saveOutcome, .saved(true))
        let saved = try XCTUnwrap(
            store.entry(
                term: latestDraft.term,
                languagePair: latestDraft.languagePair
            )
        )
        XCTAssertNotNil(saved.systemEntry)
        XCTAssertNotNil(saved.aiEntry)
    }

    func testSameCardIntentIsIgnoredWhenCurrentActionHasDisappeared() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("sentinel", forType: .string)
        let context = makeContext(kind: .word)

        let copyOutcome = try PanelResultActionPerformer.perform(
            .copy(cardID: context.cardID),
            currentCardID: context.cardID,
            currentCopyText: nil,
            currentVocabularyDraft: nil,
            vocabularyStore: store,
            pasteboard: pasteboard
        )
        let saveOutcome = try PanelResultActionPerformer.perform(
            .setSaved(cardID: context.cardID, saved: true),
            currentCardID: context.cardID,
            currentCopyText: nil,
            currentVocabularyDraft: nil,
            vocabularyStore: store,
            pasteboard: pasteboard
        )

        XCTAssertEqual(copyOutcome, .ignored)
        XCTAssertEqual(saveOutcome, .ignored)
        XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testCopyWritesExactUnicodeAndNewlines() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let pasteboard = makePasteboard()
        let context = makeContext(kind: .sentence)
        let expected = "第一行，包含“引号”\nSecond line — résumé"

        let outcome = try PanelResultActionPerformer.perform(
            .copy(cardID: context.cardID),
            currentCardID: context.cardID,
            currentCopyText: expected,
            currentVocabularyDraft: nil,
            vocabularyStore: store,
            pasteboard: pasteboard
        )

        XCTAssertEqual(outcome, .copied)
        XCTAssertEqual(pasteboard.string(forType: .string), expected)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testCopyFailureRestoresEveryPreviousPasteboardType() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let pasteboard = makePasteboard()
        let customType = NSPasteboard.PasteboardType("com.glosspop.tests.payload")
        let customData = Data([0x00, 0x01, 0xFE, 0xFF])
        let originalItem = NSPasteboardItem()
        originalItem.setString("original", forType: .string)
        originalItem.setData(customData, forType: customType)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([originalItem]))
        let context = makeContext(kind: .sentence)

        XCTAssertThrowsError(
            try PanelResultActionPerformer.perform(
                .copy(cardID: context.cardID),
                currentCardID: context.cardID,
                currentCopyText: "replacement",
                currentVocabularyDraft: nil,
                vocabularyStore: store,
                pasteboard: pasteboard,
                writeString: { _, _ in false }
            )
        ) { error in
            XCTAssertEqual(error as? PanelResultActionError, .copyFailed)
        }

        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: customType), customData)
    }

    func testCopyDoesNotTouchPasteboardWhenATypeCannotBeMaterialised() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let pasteboard = makePasteboard()
        let promisedType = NSPasteboard.PasteboardType(
            "com.glosspop.tests.promised"
        )
        let provider = EmptyPasteboardDataProvider()
        let originalItem = NSPasteboardItem()
        originalItem.setString("original", forType: .string)
        originalItem.setDataProvider(provider, forTypes: [promisedType])
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([originalItem]))
        XCTAssertTrue(pasteboard.types?.contains(promisedType) == true)
        XCTAssertNil(pasteboard.data(forType: promisedType))
        let changeCount = pasteboard.changeCount
        let context = makeContext(kind: .sentence)
        var attemptedWrite = false

        XCTAssertThrowsError(
            try PanelResultActionPerformer.perform(
                .copy(cardID: context.cardID),
                currentCardID: context.cardID,
                currentCopyText: "replacement",
                currentVocabularyDraft: nil,
                vocabularyStore: store,
                pasteboard: pasteboard,
                writeString: { _, _ in
                    attemptedWrite = true
                    return true
                }
            )
        ) { error in
            XCTAssertEqual(error as? PanelResultActionError, .copyFailed)
        }

        XCTAssertFalse(attemptedWrite)
        XCTAssertEqual(pasteboard.changeCount, changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertTrue(pasteboard.types?.contains(promisedType) == true)
    }

    func testCopyReportsWhenPreviousClipboardCannotBeRestored() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)
        let context = makeContext(kind: .sentence)

        XCTAssertThrowsError(
            try PanelResultActionPerformer.perform(
                .copy(cardID: context.cardID),
                currentCardID: context.cardID,
                currentCopyText: "replacement",
                currentVocabularyDraft: nil,
                vocabularyStore: store,
                pasteboard: pasteboard,
                writeString: { _, _ in false },
                restoreContents: { _ in false }
            )
        ) { error in
            XCTAssertEqual(
                error as? PanelResultActionError,
                .clipboardRestoreFailed
            )
        }
    }

    func testSaveAndRemoveDoNotMutatePasteboard() throws {
        let location = try makeLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = VocabularyStore(fileURL: location.file)
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("unchanged", forType: .string)
        let context = makeContext(kind: .word)
        let draft = try XCTUnwrap(
            PanelResultActionBuilder.plain(
                context: context,
                text: "机缘巧合",
                allowsVocabulary: true
            )?.vocabularyDraft
        )

        let saved = try PanelResultActionPerformer.perform(
            .setSaved(cardID: context.cardID, saved: true),
            currentCardID: context.cardID,
            currentCopyText: nil,
            currentVocabularyDraft: draft,
            vocabularyStore: store,
            pasteboard: pasteboard
        )
        XCTAssertEqual(saved, .saved(true))
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "unchanged")

        let removed = try PanelResultActionPerformer.perform(
            .setSaved(cardID: context.cardID, saved: false),
            currentCardID: context.cardID,
            currentCopyText: nil,
            currentVocabularyDraft: draft,
            vocabularyStore: store,
            pasteboard: pasteboard
        )
        XCTAssertEqual(removed, .saved(false))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(pasteboard.string(forType: .string), "unchanged")
    }

    private var dictionaryEntry: DictionaryEntry {
        var entry = DictionaryEntry()
        entry.headword = "serendipity"
        entry.pronunciation = "/ˌserənˈdɪpɪti/"
        var sense = Sense()
        sense.partOfSpeech = "noun"
        sense.translation = "机缘巧合"
        sense.definition = "A fortunate accidental discovery."
        entry.senses = [sense]
        return entry
    }

    private func makeContext(kind: InputKind) -> PanelRequestContext {
        PanelRequestContext(
            cardID: UUID(),
            source: "serendipity",
            kind: kind,
            sourceLanguage: "en",
            targetLanguage: "zh-Hans"
        )
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: .init("GlossPopTests.\(UUID().uuidString)"))
    }

    private func makeLocation() throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlossPopPanelActionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return (directory, directory.appendingPathComponent("vocabulary-v1.json"))
    }
}

private final class EmptyPasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {}
}
