import AppKit
import SwiftUI

@MainActor
final class VocabularyWindowController: NSObject, NSWindowDelegate {
    private let store: VocabularyStore
    private let exportCoordinator: VocabularyExportCoordinator
    private let frameAutosaveName: String?
    private let presentsClearConfirmationForDemo: Bool
    private var window: NSWindow?
    private var host: NSHostingController<VocabularyView>?

    init(
        store: VocabularyStore,
        frameAutosaveName: String? = "GlossPopVocabulary",
        presentsClearConfirmationForDemo: Bool = false
    ) {
        self.store = store
        exportCoordinator = VocabularyExportCoordinator(store: store)
        self.frameAutosaveName = frameAutosaveName
        self.presentsClearConfirmationForDemo = presentsClearConfirmationForDemo
    }

    func show() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.userWindowDidOpen(self)
        } else {
            NSApp.setActivationPolicy(.regular)
        }

        if window == nil {
            let hostingController = NSHostingController(
                rootView: VocabularyView(
                    store: store,
                    exportCoordinator: exportCoordinator,
                    confirmsClearInitially: presentsClearConfirmationForDemo
                )
            )
            let window = NSWindow(contentViewController: hostingController)
            exportCoordinator.window = window
            window.title = String(localized: "Vocabulary")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.tabbingMode = .disallowed
            window.toolbarStyle = .unified
            window.minSize = NSSize(width: 680, height: 440)
            window.setContentSize(NSSize(width: 840, height: 560))
            let restoredFrame = frameAutosaveName.map { name in
                window.setFrameAutosaveName(name)
                return window.setFrameUsingName(name)
            } ?? false
            if restoredFrame == false {
                let screen = NSScreen.screens.first {
                    NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
                } ?? NSScreen.screens.first
                if let screen {
                    let visibleFrame = screen.visibleFrame
                    window.setFrameOrigin(
                        NSPoint(
                            x: visibleFrame.midX - window.frame.width / 2,
                            y: visibleFrame.midY - window.frame.height / 2
                        )
                    )
                }
            }
            host = hostingController
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.userWindowWillClose(self)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func setContentSizeForDemo(_ size: NSSize) {
        window?.setContentSize(size)
    }

    func showExportPanelForDemo() {
        exportCoordinator.exportAll(.csv)
    }
}

enum VocabularyLibraryProjection {
    static func filtered(
        _ entries: [VocabularyEntry],
        query: String,
        languagePair: VocabularyLanguagePair?
    ) -> [VocabularyEntry] {
        let needle = searchKey(query)
        return entries.filter { entry in
            let pairMatches = languagePair == nil || entry.languagePair == languagePair
            return pairMatches && (
                needle.isEmpty || searchKey(searchableText(for: entry)).contains(needle)
            )
        }
    }

    static func summary(for entry: VocabularyEntry) -> String {
        if let ai = entry.aiEntry {
            for sense in ai.senses {
                if let value = firstNonEmpty(sense.translation, sense.definition) {
                    return value
                }
            }
            for idiom in ai.idioms {
                if let value = firstNonEmpty(idiom.meaning, idiom.phrase) {
                    return value
                }
            }
        }
        if let system = entry.systemEntry {
            let lines = system.body.split(
                separator: "\n",
                omittingEmptySubsequences: true
            ).map(String.init)
            if let line = lines.first(where: {
                switch SystemDictionary.classifyLine($0) {
                case .posHeader, .sectionHeader:
                    return false
                case .sense, .example, .plain:
                    return true
                }
            }) {
                return line
            }
            if let line = lines.first { return line }
            if let value = firstNonEmpty(system.headword) { return value }
        }
        return entry.term
    }

    static func languageTrack(_ pair: VocabularyLanguagePair) -> String {
        "\(trackCode(pair.sourceLanguage)) → \(trackCode(pair.targetLanguage))"
    }

    static func nextSelection(
        before: [VocabularyEntry],
        deleting id: UUID,
        after: [VocabularyEntry],
        currentSelection: UUID? = nil
    ) -> UUID? {
        guard !after.isEmpty else { return nil }
        if currentSelection != id,
           let currentSelection,
           after.contains(where: { $0.id == currentSelection }) {
            return currentSelection
        }
        let oldIndex = before.firstIndex { $0.id == id } ?? 0
        return after[min(oldIndex, after.count - 1)].id
    }

    private static func searchableText(for entry: VocabularyEntry) -> String {
        var values = [
            entry.term,
            entry.headword,
            entry.pronunciation,
            entry.languagePair.sourceLanguage,
            entry.languagePair.targetLanguage,
        ]
        if let system = entry.systemEntry {
            values += [system.headword, system.pronunciation, system.body]
        }
        if let ai = entry.aiEntry {
            values += [ai.headword, ai.pronunciation]
            for sense in ai.senses {
                values += [
                    sense.partOfSpeech,
                    sense.definition,
                    sense.translation,
                    sense.register,
                ]
                for example in sense.examples {
                    values += [example.source, example.target]
                }
                values += sense.synonyms
            }
            for idiom in ai.idioms {
                values += [idiom.phrase, idiom.meaning]
            }
        }
        return values.joined(separator: "\n")
    }

    private static func searchKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    private static func trackCode(_ code: String) -> String {
        code.caseInsensitiveCompare("auto") == .orderedSame
            ? "AUTO"
            : code.uppercased()
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

private struct VocabularyView: View {
    @Bindable var store: VocabularyStore
    @Bindable var exportCoordinator: VocabularyExportCoordinator
    @State private var query = ""
    @State private var selectedLanguagePair: VocabularyLanguagePair?
    @State private var selectedID: UUID?
    @State private var pendingDeletion: VocabularyEntry?
    @State private var confirmsClear = false

    init(
        store: VocabularyStore,
        exportCoordinator: VocabularyExportCoordinator,
        confirmsClearInitially: Bool = false
    ) {
        self.store = store
        self.exportCoordinator = exportCoordinator
        _confirmsClear = State(initialValue: confirmsClearInitially)
    }

    private var filteredEntries: [VocabularyEntry] {
        VocabularyLibraryProjection.filtered(
            store.entries,
            query: query,
            languagePair: selectedLanguagePair
        )
    }

    private var languagePairs: [VocabularyLanguagePair] {
        Array(Set(store.entries.map(\.languagePair))).sorted {
            VocabularyLibraryProjection.languageTrack($0)
                < VocabularyLibraryProjection.languageTrack($1)
        }
    }

    private var selectedEntry: VocabularyEntry? {
        guard let selectedID else { return nil }
        return store.entries.first { $0.id == selectedID }
    }

    private var blockReason: VocabularyBlockReason? {
        if case let .blocked(reason) = store.loadState { return reason }
        return nil
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            loadStateBanner
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 330)
            } detail: {
                detail
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .searchable(
            text: $query,
            placement: .toolbar,
            prompt: Text("Search Vocabulary")
        )
        .toolbar {
            ToolbarItemGroup {
                Picker(
                    String(localized: "Language Pair"),
                    selection: $selectedLanguagePair
                ) {
                    Text("All Languages")
                        .tag(nil as VocabularyLanguagePair?)
                    ForEach(languagePairs, id: \.self) { pair in
                        Text(VocabularyLibraryProjection.languageTrack(pair))
                            .tag(Optional(pair))
                    }
                }
                .pickerStyle(.menu)
                .help(String(localized: "Filter by Language Pair"))
                .disabled(languagePairs.isEmpty)

                Button {
                    pendingDeletion = selectedEntry
                } label: {
                    Label("Remove Entry", systemImage: "trash")
                }
                .disabled(selectedEntry == nil)
                .help(String(localized: "Remove Entry"))

                Menu {
                    Button {
                        exportCoordinator.exportAll(.csv)
                    } label: {
                        Label("Export All as CSV…", systemImage: "tablecells")
                    }
                    .disabled(exportCoordinator.isExporting)
                    Button {
                        exportCoordinator.exportAll(.ankiTSV)
                    } label: {
                        Label("Export All for Anki…", systemImage: "rectangle.stack")
                    }
                    .disabled(exportCoordinator.isExporting)
                    Divider()
                    Button(role: .destructive) {
                        confirmsClear = true
                    } label: {
                        Label("Clear Vocabulary…", systemImage: "trash")
                    }
                    .disabled(store.entries.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help(String(localized: "More"))
                .disabled(store.entries.isEmpty)
            }
        }
        .onAppear { repairSelection() }
        .onChange(of: filteredEntries.map(\.id)) { repairSelection() }
        .onChange(of: languagePairs) {
            if let selectedLanguagePair,
               !languagePairs.contains(selectedLanguagePair) {
                self.selectedLanguagePair = nil
            }
        }
        .onDeleteCommand {
            pendingDeletion = selectedEntry
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: hasPendingDeletion,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { removePendingEntry() }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes the saved entry from this Mac.")
        }
        .confirmationDialog(
            clearConfirmationTitle,
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("Clear Vocabulary", role: .destructive) { clearVocabulary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Preserved recovery backups are not deleted.")
        }
        .alert(item: $exportCoordinator.notice) { notice in
            switch notice.kind {
            case let .exportError(message):
                return Alert(
                    title: Text("Export Error"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case let .vocabularyError(message):
                return Alert(
                    title: Text("Vocabulary Error"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case let .exported(url, count):
                return Alert(
                    title: Text("Export Complete"),
                    message: Text(exportedMessage(url: url, count: count)),
                    primaryButton: .default(Text("Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    },
                    secondaryButton: .cancel(Text("OK"))
                )
            }
        }
    }

    @ViewBuilder
    private var loadStateBanner: some View {
        switch store.loadState {
        case .ready:
            EmptyView()
        case let .recoveredCorruptFile(backupURL):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("A damaged vocabulary file was preserved and a new library was started.")
                    Text(backupURL.lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([backupURL])
                }
                Button("Dismiss") {
                    do {
                        try store.acknowledgeRecovery()
                    } catch {
                        exportCoordinator.notice = VocabularyExportNotice(
                            kind: .vocabularyError(error.localizedDescription)
                        )
                    }
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.12))
        case let .blocked(reason):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(blockedMessage(reason))
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.red.opacity(0.1))
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if blockReason != nil {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "exclamationmark.octagon")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else if store.entries.isEmpty {
            emptySidebar
        } else if filteredEntries.isEmpty {
            emptySidebar
        } else {
            VStack(spacing: 0) {
                List(filteredEntries, selection: $selectedID) { entry in
                    VocabularyRow(entry: entry)
                        .tag(entry.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDeletion = entry
                            } label: {
                                Label("Remove Entry", systemImage: "trash")
                            }
                        }
                }
                Divider()
                HStack {
                    Text(countLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let blockReason {
            ContentUnavailableView {
                Label("Vocabulary Unavailable", systemImage: "exclamationmark.octagon")
            } description: {
                Text(blockedMessage(blockReason))
            }
        } else if store.entries.isEmpty {
            ContentUnavailableView {
                Label("No Saved Vocabulary", systemImage: "books.vertical")
            } description: {
                Text("Select a word or phrase, then use the bookmark in its result card.")
            }
        } else if filteredEntries.isEmpty {
            ContentUnavailableView {
                Label("No Matching Vocabulary", systemImage: "magnifyingglass")
            } description: {
                if !trimmedQuery.isEmpty {
                    Text("No entries match “\(trimmedQuery)”.")
                } else if let selectedLanguagePair {
                    Text(
                        "No entries use \(VocabularyLibraryProjection.languageTrack(selectedLanguagePair))."
                    )
                }
            } actions: {
                if !trimmedQuery.isEmpty {
                    Button("Clear Search") { query = "" }
                }
                if selectedLanguagePair != nil {
                    Button("Show All Languages") { selectedLanguagePair = nil }
                }
            }
        } else if let entry = selectedEntry {
            VocabularyDetail(entry: entry)
        } else {
            ContentUnavailableView {
                Label("Select a Vocabulary Entry", systemImage: "text.book.closed")
            } description: {
                Text("Choose an entry to see its complete saved dictionary card.")
            }
        }
    }

    private var emptySidebar: some View {
        VStack(spacing: 0) {
            Spacer()
            Divider()
            HStack {
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var clearConfirmationTitle: String {
        if store.count == 1 {
            return String(localized: "Clear the saved vocabulary entry?")
        }
        return String(localized: "Clear all \(store.count) vocabulary entries?")
    }

    private var deletionTitle: String {
        guard let pendingDeletion else {
            return String(localized: "Remove Vocabulary Entry?")
        }
        return String(localized: "Remove “\(pendingDeletion.headword)” from Vocabulary?")
    }

    private var hasPendingDeletion: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var countLabel: String {
        if filteredEntries.count == store.count {
            return String(localized: "\(store.count) saved")
        }
        return String(localized: "\(filteredEntries.count) of \(store.count) shown")
    }

    private func exportedMessage(url: URL, count: Int) -> String {
        if count == 1 {
            return String(
                localized: "Exported 1 vocabulary entry to “\(url.lastPathComponent)”."
            )
        }
        return String(
            localized: "Exported \(count) vocabulary entries to “\(url.lastPathComponent)”."
        )
    }

    private func repairSelection() {
        if let selectedID,
           filteredEntries.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = filteredEntries.first?.id
    }

    private func removePendingEntry() {
        guard let entry = pendingDeletion else { return }
        let before = filteredEntries
        do {
            _ = try store.remove(id: entry.id)
            let after = VocabularyLibraryProjection.filtered(
                store.entries,
                query: query,
                languagePair: selectedLanguagePair
            )
            selectedID = VocabularyLibraryProjection.nextSelection(
                before: before,
                deleting: entry.id,
                after: after,
                currentSelection: selectedID
            )
        } catch {
            exportCoordinator.notice = VocabularyExportNotice(
                kind: .vocabularyError(error.localizedDescription)
            )
        }
        pendingDeletion = nil
    }

    private func clearVocabulary() {
        do {
            try store.clear()
            selectedID = nil
            selectedLanguagePair = nil
            query = ""
        } catch {
            exportCoordinator.notice = VocabularyExportNotice(
                kind: .vocabularyError(error.localizedDescription)
            )
        }
    }

    private func blockedMessage(_ reason: VocabularyBlockReason) -> String {
        switch reason {
        case .unreadable:
            return String(localized: "The vocabulary file cannot be read. It has not been changed.")
        case let .unsupportedVersion(version):
            return String(
                localized: "This vocabulary file uses unsupported version \(version). It has not been changed."
            )
        case .recoveryFailed:
            return String(localized: "The damaged vocabulary file could not be preserved. Saving is blocked.")
        }
    }
}

private struct VocabularyRow: View {
    let entry: VocabularyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.headword)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(VocabularyLibraryProjection.languageTrack(entry.languagePair))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            let summary = VocabularyLibraryProjection.summary(for: entry)
            if summary != entry.headword {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct VocabularyDetail: View {
    let entry: VocabularyEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(VocabularyLibraryProjection.languageTrack(entry.languagePair))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(originLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.createdAt, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                if let systemEntry = entry.systemEntry {
                    if entry.aiEntry != nil {
                        Text("System Dictionary")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    SystemDictionaryCard(entry: systemEntry.runtimeEntry)
                }
                if entry.systemEntry != nil, entry.aiEntry != nil {
                    Divider()
                }
                if let aiEntry = entry.aiEntry {
                    if entry.systemEntry != nil {
                        Text("AI Dictionary")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    DictionaryCard(entry: aiEntry.runtimeEntry)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(24)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var originLabel: String {
        var labels: [String] = []
        if entry.systemEntry != nil { labels.append(String(localized: "System Dictionary")) }
        if entry.aiEntry != nil { labels.append(String(localized: "AI Dictionary")) }
        return labels.joined(separator: " + ")
    }
}

private extension VocabularySystemSnapshot {
    var runtimeEntry: SystemDictionary.Entry {
        SystemDictionary.Entry(
            headword: headword,
            pronunciation: pronunciation,
            body: body,
            hasCJK: hasCJK
        )
    }
}

private extension VocabularyAISnapshot {
    var runtimeEntry: DictionaryEntry {
        var entry = DictionaryEntry()
        entry.headword = headword
        entry.pronunciation = pronunciation
        entry.senses = senses.map { sense in
            var result = Sense()
            result.partOfSpeech = sense.partOfSpeech
            result.definition = sense.definition
            result.translation = sense.translation
            result.register = sense.register
            result.examples = sense.examples.map {
                Example(source: $0.source, target: $0.target)
            }
            result.synonyms = sense.synonyms
            return result
        }
        entry.idioms = idioms.map {
            Idiom(phrase: $0.phrase, meaning: $0.meaning)
        }
        return entry
    }
}

@MainActor
enum VocabularyDemo {
    static func makeRecoveryStore() -> VocabularyStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "GlossPopVocabularyRecoveryDemo-\(UUID().uuidString)",
                isDirectory: true
            )
        let fileURL = directory.appendingPathComponent("vocabulary-v1.json")
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try Data([0x00, 0xFF, 0x7B]).write(to: fileURL, options: .atomic)
        } catch {
            return makeStore(empty: false)
        }
        let store = VocabularyStore(fileURL: fileURL)
        _ = try? store.upsert(meetingDraft)
        return store
    }

    static func makeStore(empty: Bool) -> VocabularyStore {
        var timestamp = Date(timeIntervalSince1970: 1_785_384_000)
        var ids = [
            UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!,
            UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000003")!,
        ]
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "GlossPopVocabularyDemo-\(UUID().uuidString)",
                isDirectory: true
            )
            .appendingPathComponent("vocabulary-v1.json")
        let store = VocabularyStore(
            fileURL: fileURL,
            now: { timestamp },
            makeID: { ids.removeFirst() },
            writeData: { _, _ in }
        )
        guard !empty else { return store }

        _ = try? store.upsert(callItADayDraft)
        timestamp.addTimeInterval(3_600)
        _ = try? store.upsert(serendipityDraft)
        timestamp.addTimeInterval(3_600)
        _ = try? store.upsert(meetingDraft)
        return store
    }

    private static var meetingDraft: VocabularyDraft {
        VocabularyDraft(
            term: "会议",
            languagePair: .init(sourceLanguage: "zh-Hans", targetLanguage: "en"),
            systemEntry: .init(
                headword: "会议",
                pronunciation: "huìyì",
                body: "noun\n① （指集会） meeting\n   · 出席会议 attend a meeting\n② （指机构） council",
                hasCJK: true
            ),
            aiEntry: VocabularyAISnapshot(
                headword: "会议",
                pronunciation: "huìyì",
                senses: [
                    VocabularySense(
                        partOfSpeech: "noun",
                        definition: "a planned gathering for discussion",
                        translation: "meeting; conference",
                        register: "neutral",
                        examples: [
                            .init(
                                source: "我们明天下午有一个项目会议。",
                                target: "We have a project meeting tomorrow afternoon."
                            ),
                        ],
                        synonyms: ["conference", "session"]
                    ),
                ],
                idioms: []
            )
        )
    }

    private static var serendipityDraft: VocabularyDraft {
        VocabularyDraft(
            term: "serendipity",
            languagePair: .init(sourceLanguage: "en", targetLanguage: "zh-Hans"),
            systemEntry: nil,
            aiEntry: VocabularyAISnapshot(
                headword: "serendipity",
                pronunciation: "/ˌserənˈdɪpɪti/",
                senses: [
                    VocabularySense(
                        partOfSpeech: "noun",
                        definition: "The occurrence of a fortunate discovery by chance.",
                        translation: "机缘巧合；意外发现美好事物的运气",
                        register: "literary",
                        examples: [
                            .init(
                                source: "Finding that tiny bookshop was pure serendipity.",
                                target: "发现那家小书店纯属机缘巧合。"
                            ),
                        ],
                        synonyms: ["chance", "fortune"]
                    ),
                ],
                idioms: []
            )
        )
    }

    private static var callItADayDraft: VocabularyDraft {
        VocabularyDraft(
            term: "call it a day",
            languagePair: .init(sourceLanguage: "auto", targetLanguage: "zh-Hant"),
            systemEntry: nil,
            aiEntry: VocabularyAISnapshot(
                headword: "call it a day",
                pronunciation: "",
                senses: [
                    VocabularySense(
                        partOfSpeech: "idiom",
                        definition: "to stop working on something for the rest of the day",
                        translation: "今天到此為止；收工",
                        register: "informal",
                        examples: [
                            .init(
                                source: "We have fixed the last issue, so let's call it a day.",
                                target: "我們已修好最後一個問題，今天就到此為止吧。"
                            ),
                        ],
                        synonyms: ["stop for today", "wrap up"]
                    ),
                ],
                idioms: [
                    .init(
                        phrase: "call it quits",
                        meaning: "停止某項活動或結束一段關係"
                    ),
                ]
            )
        )
    }
}
