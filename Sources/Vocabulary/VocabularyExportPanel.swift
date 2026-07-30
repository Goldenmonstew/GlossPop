import AppKit
import Observation
import UniformTypeIdentifiers

struct VocabularyExportNotice: Identifiable {
    enum Kind {
        case exported(URL, count: Int)
        case exportError(String)
        case vocabularyError(String)
    }

    let id = UUID()
    let kind: Kind
}

enum VocabularyExportFileError: LocalizedError, Equatable {
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return String(localized: "The exported file could not be verified.")
        }
    }
}

struct VocabularyExportFileWriter: Sendable {
    private let writeData: @Sendable (Data, URL) throws -> Void
    private let readData: @Sendable (URL) throws -> Data

    init(
        writeData: @escaping @Sendable (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        },
        readData: @escaping @Sendable (URL) throws -> Data = {
            try Data(contentsOf: $0)
        }
    ) {
        self.writeData = writeData
        self.readData = readData
    }

    func writeAndVerify(_ data: Data, to destination: URL) throws {
        try writeData(data, destination)
        guard try readData(destination) == data else {
            throw VocabularyExportFileError.verificationFailed
        }
    }
}

@MainActor
@Observable
final class VocabularyExportCoordinator {
    var notice: VocabularyExportNotice?
    private(set) var isExporting = false

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private let store: VocabularyStore
    @ObservationIgnored private var savePanel: NSSavePanel?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fileWriter: VocabularyExportFileWriter

    init(
        store: VocabularyStore,
        now: @escaping () -> Date = Date.init,
        fileWriter: VocabularyExportFileWriter = VocabularyExportFileWriter()
    ) {
        self.store = store
        self.now = now
        self.fileWriter = fileWriter
    }

    func exportAll(_ format: VocabularyExportFormat) {
        guard savePanel == nil, !isExporting else { return }
        let entries = store.entries
        guard !entries.isEmpty else {
            notice = VocabularyExportNotice(
                kind: .exportError(
                    String(localized: "No saved vocabulary to export.")
                )
            )
            return
        }

        let panel = NSSavePanel()
        panel.title = String(localized: "Export Vocabulary")
        panel.prompt = String(localized: "Export")
        panel.message = exportMessage(count: entries.count)
        panel.nameFieldStringValue = defaultFilename(for: format)
        panel.allowedContentTypes = [contentType(for: format)]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        savePanel = panel

        let completion: @MainActor (NSApplication.ModalResponse) -> Void = {
            [weak self, panel] response in
            guard let self else { return }
            self.savePanel = nil
            guard response == .OK, let destination = panel.url else { return }

            self.isExporting = true
            let fileWriter = self.fileWriter
            Task { [weak self] in
                let failure = await Task.detached(priority: .userInitiated) {
                    () -> String? in
                    do {
                        let data = try VocabularyExporter.data(
                            for: format,
                            entries: entries
                        )
                        try fileWriter.writeAndVerify(data, to: destination)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }.value
                guard let self else { return }
                self.isExporting = false
                guard let failure else {
                    self.notice = VocabularyExportNotice(
                        kind: .exported(destination, count: entries.count)
                    )
                    return
                }
                let headline = String(localized: "Couldn't export the vocabulary library.")
                self.notice = VocabularyExportNotice(
                    kind: .exportError("\(headline)\n\n\(failure)")
                )
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func defaultFilename(for format: VocabularyExportFormat) -> String {
        let date = now().formatted(
            Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        )
        switch format {
        case .csv:
            return "GlossPop-\(date).csv"
        case .ankiTSV:
            return "GlossPop-Anki-\(date).txt"
        }
    }

    private func contentType(for format: VocabularyExportFormat) -> UTType {
        switch format {
        case .csv:
            return .commaSeparatedText
        case .ankiTSV:
            return .plainText
        }
    }

    private func exportMessage(count: Int) -> String {
        if count == 1 {
            return String(localized: "Exports the saved vocabulary entry.")
        }
        return String(localized: "Exports all \(count) saved vocabulary entries.")
    }
}
