import Foundation

enum VocabularyExportFormat: CaseIterable, Equatable, Sendable {
    case csv
    case ankiTSV

    var filenameExtension: String {
        switch self {
        case .csv:
            return "csv"
        case .ankiTSV:
            return "txt"
        }
    }
}

enum VocabularyExporter {
    static func data(
        for format: VocabularyExportFormat,
        entries: [VocabularyEntry]
    ) throws -> Data {
        let content = switch format {
        case .csv:
            csv(entries)
        case .ankiTSV:
            ankiTSV(entries)
        }
        return Data(content.utf8)
    }

    private static let csvHeaders = [
        "Term",
        "Source Language",
        "Target Language",
        "System Headword",
        "System Pronunciation",
        "System Dictionary",
        "AI Headword",
        "AI Pronunciation",
        "AI Dictionary",
        "Created At",
        "Updated At",
    ]

    private static func csv(_ entries: [VocabularyEntry]) -> String {
        let rows = [csvHeaders] + entries.map { entry in
            [
                entry.term,
                entry.languagePair.sourceLanguage,
                entry.languagePair.targetLanguage,
                entry.systemEntry?.headword ?? "",
                entry.systemEntry?.pronunciation ?? "",
                entry.systemEntry?.body ?? "",
                entry.aiEntry?.headword ?? "",
                entry.aiEntry?.pronunciation ?? "",
                plainAI(entry.aiEntry),
                timestamp(entry.createdAt),
                timestamp(entry.updatedAt),
            ]
        }
        return rows
            .map { $0.map(csvField).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    private static func csvField(_ value: String) -> String {
        let safeValue: String
        if let first = value.first(where: { !$0.isWhitespace }),
           ["=", "+", "-", "@"].contains(first) {
            safeValue = "'" + value
        } else {
            safeValue = value
        }
        return "\"\(safeValue.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func ankiTSV(_ entries: [VocabularyEntry]) -> String {
        var lines = [
            "#separator:tab",
            "#html:true",
            "#columns:Front\tBack\tTags",
            "#tags column:3",
        ]
        lines.append(contentsOf: entries.map { entry in
            [
                ankiFront(entry),
                ankiBack(entry),
                ankiTags(entry),
            ].joined(separator: "\t")
        })
        return lines.joined(separator: "\n") + "\n"
    }

    private static func ankiFront(_ entry: VocabularyEntry) -> String {
        let source = html(entry.languagePair.sourceLanguage)
        let target = html(entry.languagePair.targetLanguage)
        return """
        <span dir="auto">\(html(entry.term))</span><br><small>\(source) → \(target)</small>
        """
    }

    private static func ankiBack(_ entry: VocabularyEntry) -> String {
        var blocks: [String] = []

        if entry.headword != entry.term, !isBlank(entry.headword) {
            blocks.append("<b>Headword</b><br>\(html(entry.headword))")
        }

        if !isBlank(entry.pronunciation) {
            blocks.append(
                "<b>Pronunciation</b><br>\(html(entry.pronunciation))"
            )
        }

        if let system = entry.systemEntry {
            var details: [String] = []
            if !isBlank(system.headword), system.headword != entry.headword {
                details.append(html(system.headword))
            }
            if !isBlank(system.pronunciation),
               system.pronunciation != entry.pronunciation {
                details.append(html(system.pronunciation))
            }
            if !isBlank(system.body) {
                details.append(html(system.body))
            }
            if !details.isEmpty {
                blocks.append(
                    (["<b>System Dictionary</b>"] + details)
                        .joined(separator: "<br>")
                )
            }
        }

        if let ai = entry.aiEntry {
            var details: [String] = []
            if !isBlank(ai.headword), ai.headword != entry.headword {
                details.append(html(ai.headword))
            }
            if !isBlank(ai.pronunciation),
               ai.pronunciation != entry.pronunciation {
                details.append(html(ai.pronunciation))
            }
            let body = plainAI(ai)
            if !body.isEmpty {
                details.append(html(body))
            }
            if !details.isEmpty {
                blocks.append(
                    (["<b>AI Dictionary</b>"] + details)
                        .joined(separator: "<br>")
                )
            }
        }

        if blocks.isEmpty {
            return "<b>Headword</b><br>\(html(entry.headword))"
        }
        return blocks.joined(separator: "<br><br>")
    }

    private static func plainAI(_ entry: VocabularyAISnapshot?) -> String {
        guard let entry else { return "" }
        var blocks: [String] = []
        var senseNumber = 0

        for sense in entry.senses {
            var details: [String] = []
            append("Part of speech", value: sense.partOfSpeech, to: &details)
            append("Register", value: sense.register, to: &details)
            append("Definition", value: sense.definition, to: &details)
            append("Translation", value: sense.translation, to: &details)

            let examples = sense.examples.compactMap { example -> String? in
                let values = [example.source, example.target].filter { !isBlank($0) }
                guard !values.isEmpty else { return nil }
                return "- " + values.joined(separator: " — ")
            }
            if !examples.isEmpty {
                details.append("Examples:\n" + examples.joined(separator: "\n"))
            }

            let synonyms = sense.synonyms.filter { !isBlank($0) }
            if !synonyms.isEmpty {
                details.append("Synonyms: " + synonyms.joined(separator: ", "))
            }

            guard !details.isEmpty else { continue }
            senseNumber += 1
            blocks.append(
                (["Sense \(senseNumber)"] + details).joined(separator: "\n")
            )
        }

        let idioms = entry.idioms.compactMap { idiom -> String? in
            let values = [idiom.phrase, idiom.meaning].filter { !isBlank($0) }
            guard !values.isEmpty else { return nil }
            return "- " + values.joined(separator: " — ")
        }
        if !idioms.isEmpty {
            blocks.append("Idioms:\n" + idioms.joined(separator: "\n"))
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func append(
        _ label: String,
        value: String,
        to lines: inout [String]
    ) {
        guard !isBlank(value) else { return }
        lines.append("\(label): \(value)")
    }

    private static func html(_ value: String) -> String {
        var result = ""
        for character in value {
            switch character {
            case "&":
                result += "&amp;"
            case "<":
                result += "&lt;"
            case ">":
                result += "&gt;"
            case "\"":
                result += "&quot;"
            case "'":
                result += "&#39;"
            case "\t":
                result += "&emsp;"
            default:
                if character.isNewline {
                    result += "<br>"
                } else {
                    result.append(character)
                }
            }
        }
        return result
    }

    private static func ankiTags(_ entry: VocabularyEntry) -> String {
        var tags = ["glosspop"]
        let source = tagComponent(entry.languagePair.sourceLanguage)
        let target = tagComponent(entry.languagePair.targetLanguage)
        if !source.isEmpty { tags.append("source-\(source)") }
        if !target.isEmpty { tags.append("target-\(target)") }
        if entry.systemEntry != nil { tags.append("system-dictionary") }
        if entry.aiEntry != nil { tags.append("ai-dictionary") }
        return tags.joined(separator: " ")
    }

    private static func tagComponent(_ value: String) -> String {
        let lowered = value.lowercased(with: Locale(identifier: "en_US_POSIX"))
        let mapped = lowered.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-"
        }.joined()
        return mapped
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
