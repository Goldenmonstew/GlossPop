import CoreServices
import Foundation

// macOS built-in dictionary lookup (DictionaryServices) — instant (~1–30ms), offline, no LLM. Uses whatever
// dictionaries the user has enabled in Dictionary.app; if a 简体中文-English dictionary is enabled the result
// is bilingual, otherwise it's the monolingual (e.g. Oxford English) entry.
enum SystemDictionary {
    struct Entry: Sendable {
        let headword: String
        let pronunciation: String
        let body: String        // the definition text (everything after headword | pron)
        let hasCJK: Bool        // true if the entry contains Chinese — used to nudge enabling a CN dictionary
    }

    /// Look up a term. nil when it isn't in any enabled dictionary (caller falls back to the LLM).
    static func lookup(_ term: String) -> Entry? {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let range = CFRangeMake(0, t.utf16.count)
        guard let raw = DCSCopyTextDefinition(nil, t as CFString, range)?.takeRetainedValue() as String?,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return parse(raw: raw, term: t)
    }

    /// Parse one DCS raw entry string (separated out so tests can feed captured fixtures without DCS).
    static func parse(raw: String, term t: String) -> Entry? {
        let hasCJK = raw.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        // Standard Oxford-style layout: "headword | pron | POS definition…". Split on the FIRST two " | "
        // only (definitions themselves contain " | " between examples).
        let parts = raw.components(separatedBy: " | ")
        if parts.count == 1 {
            // 汉英 / CJK layouts have NO " | " separators — the whole entry is one run-on string
            // ("学习 xuéxí verb ① …"). parts.first would render the ENTIRE entry as the bold headline
            // AND duplicate it in the body. Use the term as the headword and strip it from the body.
            var rest = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Same phrase guard as the piped layout: a spaced phrase whose pipe-less entry
            // doesn't OPEN with the phrase itself is a first-word sub-term hit → miss, let AI handle it.
            if t.contains(where: { $0 == " " }), !rest.hasPrefix(t),
               !phraseNorm(rest).hasPrefix(phraseNorm(t)) { return nil }
            if rest.hasPrefix(t) {
                rest = String(rest.dropFirst(t.count)).trimmingCharacters(in: .whitespaces)
            }
            // Leading pinyin tokens (e.g. "xuéxí", "rénɡōnɡ zhìnénɡ", "yījǔ-liǎnɡdé") → pronunciation.
            // Pinyin always carries a non-ASCII letter (tone mark / ɡ), which keeps English body words
            // ("verb", "idiom", "kill") and CJK from being eaten.
            var pron: [String] = []
            var tokens = rest.split(separator: " ", omittingEmptySubsequences: true)
            while let tok = tokens.first, pron.count < 4, isPinyinToken(String(tok)) {
                pron.append(String(tok)); tokens.removeFirst()
            }
            let body = pron.isEmpty ? rest : tokens.joined(separator: " ")
            return Entry(headword: t, pronunciation: pron.joined(separator: " "),
                         body: formatBody(body), hasCJK: hasCJK)
        }
        let headword = parts.first ?? t
        // Phrase guard: for a multi-word term, DCS often returns just the FIRST word's entry. That's a
        // sub-term hit, not the phrase — treat it as a miss so AI / translation handles the phrase.
        // Lenient compare: trailing punctuation, curly vs straight apostrophes, case, diacritics
        // and whitespace runs must NOT reject a legitimate phrase hit.
        if t.contains(where: { $0 == " " }), phraseNorm(headword) != phraseNorm(t) { return nil }
        let pron = parts.count >= 3 ? parts[1] : ""
        let rawBody = parts.count >= 3 ? parts[2...].joined(separator: " | ")
                    : (parts.count == 2 ? parts[1] : raw)
        return Entry(headword: headword, pronunciation: pron,
                     body: formatBody(rawBody), hasCJK: hasCJK)
    }

    /// Lenient phrase comparison: case/diacritic folded, curly→straight apostrophe, edge punctuation
    /// trimmed, internal whitespace collapsed ("Ice  cream." matches headword "ice cream").
    private static func phraseNorm(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Pinyin (or zhuyin-ish romanization) token: pure letters/hyphen/apostrophe with at least one
    /// NON-ASCII letter (tone marks, ɡ) — never a plain English word and never CJK.
    private static func isPinyinToken(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 24 else { return false }
        var hasNonASCIILetter = false
        for scalar in s.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) { return false }            // CJK → body, stop
            if scalar.properties.isAlphabetic {
                if !scalar.isASCII { hasNonASCIILetter = true }
            } else if scalar.value != 0x2D, scalar.value != 0x27, scalar.value != 0x2019 { // - ' ’
                return false
            }
        }
        return hasNonASCIILetter
    }

    // DCS returns the whole entry as ONE flat run-on string. Insert line breaks so it's readable instead of
    // a wall of text: each part-of-speech section, numbered sense, "•" sub-sense, and ORIGIN/etc. on its own line.
    private static let posWords = "noun|verb|adjective|adverb|pronoun|preposition|conjunction|exclamation|determiner|abbreviation|phrase"
    static func formatBody(_ raw: String) -> String {
        var s = raw
        func re(_ pat: String, _ tmpl: String) {
            s = s.replacingOccurrences(of: pat, with: tmpl, options: .regularExpression)
        }
        // Bilingual (英汉) dictionaries: circled-number senses ①②③… and example markers (▸ / ‣).
        re(#"\s*([①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳])\s*"#, "\n$1 ")
        for mark in ["▸", "‣"] { s = s.replacingOccurrences(of: mark, with: "\n   · ") }
        // English (Oxford) layout: POS sections, numbered senses, bullets, trailing headers.
        re(#"\s*\b(\#(posWords))\s+\|\s+([^|]+?)\s+\|\s+"#, "\n\n$1  $2\n") // embedded "POS | pron |" → header
        re(#"([.:)])\s+(\d+)\s+"#, "$1\n$2. ")                              // numbered senses → own line
        s = s.replacingOccurrences(of: " • ", with: "\n   · ")              // bullet sub-senses
        re(#"\s+(ORIGIN|PHRASES|DERIVATIVES|PHRASAL VERBS?|USAGE)\b"#, "\n\n$1 ") // section headers
        re(#"·[ ]+"#, "· ")        // collapse double space after a bullet
        re(#"\n{3,}"#, "\n\n")     // collapse runs of blank lines
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Look Up-style typography for the formatted body

    enum BodyLineKind: Equatable { case posHeader, sectionHeader, sense, example, plain }

    /// Classify one formatBody output line so the card can style it (pure — unit-tested).
    static func classifyLine(_ line: String) -> BodyLineKind {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("·") { return .example }
        if let first = t.unicodeScalars.first, (0x2460...0x2473).contains(first.value) { return .sense } // ①–⑳
        if t.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil { return .sense }
        if t.range(of: #"^(ORIGIN|PHRASES|DERIVATIVES|PHRASAL VERBS?|USAGE)\b"#, options: .regularExpression) != nil {
            return .sectionHeader
        }
        if t.range(of: #"^(\#(posWords))\b"#, options: .regularExpression) != nil { return .posHeader }
        return .plain
    }

    /// Names of all dictionaries macOS has available (for the Settings list). Uses DictionaryServices via
    /// dlsym so a missing symbol degrades to [] instead of crashing. The user enables/downloads them in
    /// Dictionary.app — there is no third-party API to toggle them (Apple restriction).
    static func availableNames() -> [String] {
        guard let handle = dlopen(nil, RTLD_NOW) else { return [] }
        guard let copySym = dlsym(handle, "DCSCopyAvailableDictionaries"),
              let nameSym = dlsym(handle, "DCSDictionaryGetName") else { return [] }
        typealias CopyFn = @convention(c) () -> Unmanaged<CFSet>?
        typealias NameFn = @convention(c) (CFTypeRef) -> Unmanaged<CFString>?
        let copy = unsafeBitCast(copySym, to: CopyFn.self)
        let name = unsafeBitCast(nameSym, to: NameFn.self)
        guard let set = copy()?.takeRetainedValue() else { return [] }   // "Copy" → we own it
        let names = (set as NSSet).allObjects.compactMap { d -> String? in
            name(d as CFTypeRef)?.takeUnretainedValue() as String?
        }
        return Array(Set(names)).sorted()
    }
}
