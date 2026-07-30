import AppKit
import Foundation

struct PanelRequestContext: Equatable, Sendable {
    let cardID: UUID
    let source: String
    let kind: InputKind
    let sourceLanguage: String
    let targetLanguage: String
}

struct PanelResultPayload: Equatable, Sendable {
    let cardID: UUID
    let copyText: String
    let vocabularyDraft: VocabularyDraft?
}

enum ResultCardEvent: Equatable, Sendable {
    case copy(cardID: UUID)
    case setSaved(cardID: UUID, saved: Bool)
}

enum PanelResultActionOutcome: Equatable {
    case ignored
    case copied
    case saved(Bool)
}

enum PanelResultActionError: LocalizedError, Equatable {
    case copyFailed
    case clipboardRestoreFailed

    var errorDescription: String? {
        switch self {
        case .copyFailed:
            return String(localized: "The result could not be copied.")
        case .clipboardRestoreFailed:
            return String(
                localized: "The previous clipboard contents could not be restored."
            )
        }
    }
}

enum PanelResultActionBuilder {
    static func word(
        context: PanelRequestContext,
        systemEntry: SystemDictionary.Entry?,
        aiEntry: DictionaryEntry?
    ) -> PanelResultPayload? {
        guard context.kind == .word || context.kind == .phrase else { return nil }
        let copyText = firstNonEmpty(
            systemEntry.flatMap { firstNonEmpty($0.body, $0.headword) },
            aiEntry.flatMap(aiCopyText)
        )
        guard let copyText else { return nil }

        return PanelResultPayload(
            cardID: context.cardID,
            copyText: copyText,
            vocabularyDraft: VocabularyDraft(
                term: context.source,
                languagePair: VocabularyLanguagePair(
                    sourceLanguage: context.sourceLanguage,
                    targetLanguage: context.targetLanguage
                ),
                systemEntry: systemEntry.map(VocabularySystemSnapshot.init),
                aiEntry: aiEntry.map(VocabularyAISnapshot.init)
            )
        )
    }

    static func plain(
        context: PanelRequestContext,
        text: String,
        allowsVocabulary: Bool
    ) -> PanelResultPayload? {
        guard let copyText = firstNonEmpty(text) else { return nil }
        let canSave = allowsVocabulary && (context.kind == .word || context.kind == .phrase)
        let draft: VocabularyDraft? = canSave
            ? VocabularyDraft(
                term: context.source,
                languagePair: VocabularyLanguagePair(
                    sourceLanguage: context.sourceLanguage,
                    targetLanguage: context.targetLanguage
                ),
                systemEntry: nil,
                aiEntry: VocabularyAISnapshot(
                    headword: context.source,
                    pronunciation: "",
                    senses: [
                        VocabularySense(
                            partOfSpeech: "",
                            definition: "",
                            translation: copyText,
                            register: "",
                            examples: [],
                            synonyms: []
                        ),
                    ],
                    idioms: []
                )
            )
            : nil
        return PanelResultPayload(
            cardID: context.cardID,
            copyText: copyText,
            vocabularyDraft: draft
        )
    }

    static func enrichmentDraft(
        existing: VocabularyEntry,
        with draft: VocabularyDraft
    ) -> VocabularyDraft? {
        let systemEntry = existing.systemEntry == nil ? draft.systemEntry : nil
        let aiEntry = existing.aiEntry == nil ? draft.aiEntry : nil
        guard systemEntry != nil || aiEntry != nil else { return nil }
        return VocabularyDraft(
            term: existing.term,
            languagePair: existing.languagePair,
            systemEntry: systemEntry,
            aiEntry: aiEntry
        )
    }

    private static func aiCopyText(_ entry: DictionaryEntry) -> String? {
        for sense in entry.senses {
            if let value = firstNonEmpty(sense.translation, sense.definition) {
                return value
            }
        }
        for idiom in entry.idioms {
            if let value = firstNonEmpty(idiom.meaning, idiom.phrase) {
                return value
            }
        }
        return nil
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy.compactMap { value in
            guard let value else { return nil }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : value
        }.first
    }
}

@MainActor
enum PanelResultActionPerformer {
    static func perform(
        _ event: ResultCardEvent,
        currentCardID: UUID?,
        currentCopyText: String?,
        currentVocabularyDraft: VocabularyDraft?,
        vocabularyStore: VocabularyStore,
        pasteboard: NSPasteboard = .general,
        writeString: ((String, NSPasteboard) -> Bool)? = nil,
        restoreContents: ((NSPasteboard) -> Bool)? = nil
    ) throws -> PanelResultActionOutcome {
        guard event.cardID == currentCardID else { return .ignored }

        switch event {
        case .copy:
            guard let text = currentCopyText else { return .ignored }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PanelResultActionError.copyFailed
            }
            guard let previousContents = PasteboardSnapshot(pasteboard) else {
                throw PanelResultActionError.copyFailed
            }
            pasteboard.clearContents()
            let didWrite = writeString?(text, pasteboard)
                ?? pasteboard.setString(text, forType: .string)
            guard didWrite else {
                let didRestore = restoreContents?(pasteboard)
                    ?? previousContents.restore(to: pasteboard)
                guard didRestore else {
                    throw PanelResultActionError.clipboardRestoreFailed
                }
                throw PanelResultActionError.copyFailed
            }
            return .copied

        case let .setSaved(_, saved):
            guard let draft = currentVocabularyDraft else { return .ignored }
            if saved {
                _ = try vocabularyStore.upsert(draft)
            } else {
                _ = try vocabularyStore.remove(
                    term: draft.term,
                    languagePair: draft.languagePair
                )
            }
            return .saved(
                vocabularyStore.contains(
                    term: draft.term,
                    languagePair: draft.languagePair
                )
            )
        }
    }
}

private struct PasteboardSnapshot {
    private struct Value {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private let items: [[Value]]

    init?(_ pasteboard: NSPasteboard) {
        var captured: [[Value]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var values: [Value] = []
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    return nil
                }
                values.append(Value(type: type, data: data))
            }
            captured.append(values)
        }
        items = captured
    }

    func restore(to pasteboard: NSPasteboard) -> Bool {
        var restored: [NSPasteboardItem] = []
        for values in items {
            let item = NSPasteboardItem()
            for value in values {
                guard item.setData(value.data, forType: value.type) else {
                    return false
                }
            }
            restored.append(item)
        }
        pasteboard.clearContents()
        return restored.isEmpty || pasteboard.writeObjects(restored)
    }
}

extension ResultCardEvent {
    var cardID: UUID {
        switch self {
        case let .copy(cardID), let .setSaved(cardID, _):
            return cardID
        }
    }
}
