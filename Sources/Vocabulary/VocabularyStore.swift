import Foundation
import Observation

struct VocabularyLanguagePair: Codable, Hashable, Sendable, Equatable {
    var sourceLanguage: String
    var targetLanguage: String
}

enum VocabularyOrigin: String, Codable, Hashable, Sendable {
    case systemDictionary
    case aiDictionary
}

struct VocabularySystemSnapshot: Codable, Equatable, Sendable {
    var headword: String
    var pronunciation: String
    var body: String
    var hasCJK: Bool

    init(headword: String, pronunciation: String, body: String, hasCJK: Bool) {
        self.headword = headword
        self.pronunciation = pronunciation
        self.body = body
        self.hasCJK = hasCJK
    }

    init(_ entry: SystemDictionary.Entry) {
        self.init(
            headword: entry.headword,
            pronunciation: entry.pronunciation,
            body: entry.body,
            hasCJK: entry.hasCJK
        )
    }
}

struct VocabularyExample: Codable, Equatable, Sendable {
    var source: String
    var target: String
}

struct VocabularySense: Codable, Equatable, Sendable {
    var partOfSpeech: String
    var definition: String
    var translation: String
    var register: String
    var examples: [VocabularyExample]
    var synonyms: [String]
}

struct VocabularyIdiom: Codable, Equatable, Sendable {
    var phrase: String
    var meaning: String
}

struct VocabularyAISnapshot: Codable, Equatable, Sendable {
    var headword: String
    var pronunciation: String
    var senses: [VocabularySense]
    var idioms: [VocabularyIdiom]

    init(
        headword: String,
        pronunciation: String,
        senses: [VocabularySense],
        idioms: [VocabularyIdiom]
    ) {
        self.headword = headword
        self.pronunciation = pronunciation
        self.senses = senses
        self.idioms = idioms
    }

    init(_ entry: DictionaryEntry) {
        self.init(
            headword: entry.headword,
            pronunciation: entry.pronunciation,
            senses: entry.senses.map {
                VocabularySense(
                    partOfSpeech: $0.partOfSpeech,
                    definition: $0.definition,
                    translation: $0.translation,
                    register: $0.register,
                    examples: $0.examples.map {
                        VocabularyExample(source: $0.source, target: $0.target)
                    },
                    synonyms: $0.synonyms
                )
            },
            idioms: entry.idioms.map {
                VocabularyIdiom(phrase: $0.phrase, meaning: $0.meaning)
            }
        )
    }
}

struct VocabularyDraft: Equatable, Sendable {
    var term: String
    var languagePair: VocabularyLanguagePair
    var systemEntry: VocabularySystemSnapshot?
    var aiEntry: VocabularyAISnapshot?
}

struct VocabularyEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var term: String
    let languagePair: VocabularyLanguagePair
    var systemEntry: VocabularySystemSnapshot?
    var aiEntry: VocabularyAISnapshot?
    let createdAt: Date
    var updatedAt: Date

    var origins: Set<VocabularyOrigin> {
        var result: Set<VocabularyOrigin> = []
        if systemEntry != nil { result.insert(.systemDictionary) }
        if aiEntry != nil { result.insert(.aiDictionary) }
        return result
    }

    var headword: String {
        Self.firstNonEmpty(aiEntry?.headword, systemEntry?.headword) ?? term
    }

    var pronunciation: String {
        Self.firstNonEmpty(aiEntry?.pronunciation, systemEntry?.pronunciation) ?? ""
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy.compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : value
        }.first
    }
}

struct VocabularyArchive: Codable, Equatable, Sendable {
    let schemaVersion: Int
    var entries: [VocabularyEntry]
}

enum VocabularyBlockReason: Equatable, Sendable {
    case unreadable
    case unsupportedVersion(Int)
    case recoveryFailed
}

enum VocabularyLoadState: Equatable, Sendable {
    case ready
    case recoveredCorruptFile(URL)
    case blocked(VocabularyBlockReason)
}

enum VocabularyStoreError: LocalizedError, Equatable {
    case emptyTerm
    case emptyLanguage
    case emptyContent
    case blocked(VocabularyBlockReason)

    var errorDescription: String? {
        switch self {
        case .emptyTerm:
            return String(localized: "A vocabulary entry needs a term.")
        case .emptyLanguage:
            return String(
                localized: "A vocabulary entry needs both source and target languages."
            )
        case .emptyContent:
            return String(localized: "A vocabulary entry needs dictionary content.")
        case let .blocked(reason):
            switch reason {
            case .unreadable:
                return String(localized: "The vocabulary library cannot be read.")
            case let .unsupportedVersion(version):
                return String(
                    localized: "Vocabulary library version \(version) is not supported."
                )
            case .recoveryFailed:
                return String(
                    localized: "The damaged vocabulary library could not be preserved."
                )
            }
        }
    }
}

@MainActor
@Observable
final class VocabularyStore {
    static let shared = VocabularyStore()

    private static let schemaVersion = 1
    private static let filename = "vocabulary-v1.json"
    private static let pendingBackupPrefix = "vocabulary-v1.corrupt-pending-"
    private static let keptBackupPrefix = "vocabulary-v1.corrupt-kept-"
    private static let legacyBackupPrefix = "vocabulary-v1.corrupt-"

    private(set) var entries: [VocabularyEntry] = []
    private(set) var loadState: VocabularyLoadState = .ready

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let makeID: () -> UUID
    @ObservationIgnored private let readData: (URL) throws -> Data
    @ObservationIgnored private let writeData: (Data, URL) throws -> Void
    @ObservationIgnored private let moveItem: (URL, URL) throws -> Void

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> UUID = UUID.init,
        readData: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) },
        writeData: @escaping (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        },
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.now = now
        self.makeID = makeID
        self.readData = readData
        self.writeData = writeData
        self.moveItem = moveItem ?? { try fileManager.moveItem(at: $0, to: $1) }
        load()
    }

    var count: Int { entries.count }

    static func transient() -> VocabularyStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "GlossPopVocabularyTransient-\(UUID().uuidString)",
                isDirectory: true
            )
        return VocabularyStore(
            fileURL: directory.appendingPathComponent(filename),
            writeData: { _, _ in }
        )
    }

    func entry(term: String, languagePair: VocabularyLanguagePair) -> VocabularyEntry? {
        let key = Self.key(term: term, languagePair: languagePair)
        return entries.first { Self.key(for: $0) == key }
    }

    func contains(term: String, languagePair: VocabularyLanguagePair) -> Bool {
        entry(term: term, languagePair: languagePair) != nil
    }

    @discardableResult
    func upsert(_ draft: VocabularyDraft) throws -> VocabularyEntry {
        try ensureWritable()
        let prepared = try Self.prepare(draft)
        let timestamp = now()
        let draftKey = Self.key(term: prepared.term, languagePair: prepared.languagePair)
        var candidate = entries

        let saved: VocabularyEntry
        if let index = candidate.firstIndex(where: { Self.key(for: $0) == draftKey }) {
            let existing = candidate.remove(at: index)
            saved = VocabularyEntry(
                id: existing.id,
                term: prepared.term,
                languagePair: existing.languagePair,
                systemEntry: prepared.systemEntry ?? existing.systemEntry,
                aiEntry: prepared.aiEntry ?? existing.aiEntry,
                createdAt: existing.createdAt,
                updatedAt: timestamp
            )
        } else {
            saved = VocabularyEntry(
                id: makeID(),
                term: prepared.term,
                languagePair: prepared.languagePair,
                systemEntry: prepared.systemEntry,
                aiEntry: prepared.aiEntry,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }

        candidate.insert(saved, at: 0)
        try persist(candidate)
        entries = candidate
        return saved
    }

    @discardableResult
    func remove(id: UUID) throws -> Bool {
        try ensureWritable()
        guard entries.contains(where: { $0.id == id }) else { return false }
        let candidate = entries.filter { $0.id != id }
        try persist(candidate)
        entries = candidate
        return true
    }

    @discardableResult
    func remove(term: String, languagePair: VocabularyLanguagePair) throws -> Bool {
        try ensureWritable()
        let target = Self.key(term: term, languagePair: languagePair)
        guard entries.contains(where: { Self.key(for: $0) == target }) else { return false }
        let candidate = entries.filter { Self.key(for: $0) != target }
        try persist(candidate)
        entries = candidate
        return true
    }

    func clear() throws {
        try ensureWritable()
        try persist([])
        entries = []
    }

    func acknowledgeRecovery() throws {
        guard case let .recoveredCorruptFile(backupURL) = loadState else { return }
        do {
            try moveItem(backupURL, Self.keptBackupURL(for: backupURL))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // The user may have reviewed and deleted the backup in Finder before dismissing.
        }
        loadState = .ready
        restorePendingRecoveryState()
    }

    private func ensureWritable() throws {
        if case let .blocked(reason) = loadState {
            throw VocabularyStoreError.blocked(reason)
        }
    }

    private func persist(_ candidate: [VocabularyEntry]) throws {
        let archive = VocabularyArchive(
            schemaVersion: Self.schemaVersion,
            entries: candidate
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(archive)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeData(data, fileURL)
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            restorePendingRecoveryState()
            return
        }

        let data: Data
        do {
            data = try readData(fileURL)
        } catch {
            loadState = .blocked(.unreadable)
            return
        }

        do {
            let version = try Self.archiveVersion(in: data)
            guard version == Self.schemaVersion else {
                loadState = .blocked(.unsupportedVersion(version))
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let archive = try decoder.decode(VocabularyArchive.self, from: data)
            entries = try Self.validated(archive.entries)
            restorePendingRecoveryState()
        } catch {
            recoverCorruptFile()
        }
    }

    private func recoverCorruptFile() {
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(
                "\(Self.pendingBackupPrefix)\(makeID().uuidString).json"
            )
        do {
            try moveItem(fileURL, backupURL)
            entries = []
            loadState = .recoveredCorruptFile(backupURL)
        } catch {
            loadState = .blocked(.recoveryFailed)
        }
    }

    private func restorePendingRecoveryState() {
        guard case .ready = loadState,
              let backupURL = pendingRecoveryURLs().first else { return }
        loadState = .recoveredCorruptFile(backupURL)
    }

    private func pendingRecoveryURLs() -> [URL] {
        let directory = fileURL.deletingLastPathComponent()
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return contents
            .filter { url in
                let name = url.lastPathComponent
                guard name.hasSuffix(".json"),
                      !name.hasPrefix(Self.keptBackupPrefix) else { return false }
                return name.hasPrefix(Self.pendingBackupPrefix)
                    || name.hasPrefix(Self.legacyBackupPrefix)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func keptBackupURL(for backupURL: URL) -> URL {
        let name = backupURL.lastPathComponent
        let suffix: Substring
        if name.hasPrefix(pendingBackupPrefix) {
            suffix = name.dropFirst(pendingBackupPrefix.count)
        } else if name.hasPrefix(legacyBackupPrefix) {
            suffix = name.dropFirst(legacyBackupPrefix.count)
        } else {
            suffix = Substring(name)
        }
        return backupURL.deletingLastPathComponent()
            .appendingPathComponent("\(keptBackupPrefix)\(suffix)")
    }

    private static func archiveVersion(in data: Data) throws -> Int {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["schemaVersion"] as? NSNumber,
              number.doubleValue == Double(number.intValue) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return number.intValue
    }

    private static func validated(_ entries: [VocabularyEntry]) throws -> [VocabularyEntry] {
        var ids: Set<UUID> = []
        var keys: Set<String> = []
        var result: [VocabularyEntry] = []

        for entry in entries {
            guard ids.insert(entry.id).inserted,
                  keys.insert(key(for: entry)).inserted else {
                throw CocoaError(.coderReadCorrupt)
            }
            let prepared = try prepare(
                VocabularyDraft(
                    term: entry.term,
                    languagePair: entry.languagePair,
                    systemEntry: entry.systemEntry,
                    aiEntry: entry.aiEntry
                )
            )
            result.append(
                VocabularyEntry(
                    id: entry.id,
                    term: prepared.term,
                    languagePair: prepared.languagePair,
                    systemEntry: prepared.systemEntry,
                    aiEntry: prepared.aiEntry,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt
                )
            )
        }
        return result
    }

    private static func prepare(_ draft: VocabularyDraft) throws -> VocabularyDraft {
        let term = collapsedWhitespace(draft.term)
        guard !term.isEmpty else { throw VocabularyStoreError.emptyTerm }

        let pair = VocabularyLanguagePair(
            sourceLanguage: normalisedLanguage(draft.languagePair.sourceLanguage),
            targetLanguage: normalisedLanguage(draft.languagePair.targetLanguage)
        )
        guard !pair.sourceLanguage.isEmpty, !pair.targetLanguage.isEmpty else {
            throw VocabularyStoreError.emptyLanguage
        }
        let systemEntry = hasContent(draft.systemEntry) ? draft.systemEntry : nil
        let aiEntry = hasContent(draft.aiEntry) ? draft.aiEntry : nil
        guard systemEntry != nil || aiEntry != nil else {
            throw VocabularyStoreError.emptyContent
        }

        return VocabularyDraft(
            term: term.precomposedStringWithCanonicalMapping,
            languagePair: pair,
            systemEntry: systemEntry,
            aiEntry: aiEntry
        )
    }

    private static func hasContent(_ entry: VocabularySystemSnapshot?) -> Bool {
        guard let entry else { return false }
        return [entry.headword, entry.pronunciation, entry.body].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func hasContent(_ entry: VocabularyAISnapshot?) -> Bool {
        guard let entry else { return false }
        if entry.senses.contains(where: { sense in
            [sense.definition, sense.translation].contains(where: { !isBlank($0) })
                || sense.examples.contains { !isBlank($0.source) || !isBlank($0.target) }
                || sense.synonyms.contains { !isBlank($0) }
        }) {
            return true
        }
        return entry.idioms.contains {
            !isBlank($0.meaning)
        }
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func key(for entry: VocabularyEntry) -> String {
        key(term: entry.term, languagePair: entry.languagePair)
    }

    private static func key(term: String, languagePair: VocabularyLanguagePair) -> String {
        let pair = VocabularyLanguagePair(
            sourceLanguage: normalisedLanguage(languagePair.sourceLanguage),
            targetLanguage: normalisedLanguage(languagePair.targetLanguage)
        )
        return [
            normalisedTerm(term),
            pair.sourceLanguage.lowercased(),
            pair.targetLanguage.lowercased(),
        ].joined(separator: "\u{1F}")
    }

    private static func normalisedTerm(_ value: String) -> String {
        collapsedWhitespace(value)
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    private static func normalisedLanguage(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !trimmed.isEmpty else { return "" }
        return Locale.canonicalLanguageIdentifier(from: trimmed)
    }

    private static func collapsedWhitespace(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("GlossPop", isDirectory: true)
            .appendingPathComponent(filename)
    }
}
