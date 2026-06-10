import Foundation

enum StructuredResult: Sendable {
    case dictionary(DictionaryEntry)
    case sentence(SentenceAnalysis)
}

// A refine engine that can also produce input-aware STRUCTURED output (PLAN §2.5).
// Word/phrase → bilingual dictionary: definition in `secondLanguage`, meaning in `firstLanguage`.
// Sentence → translate into `firstLanguage` + syntax.
protocol StructuredRefineEngine: RefineEngine {
    func structured(kind: InputKind, source: String, firstLanguage: String, secondLanguage: String) async throws -> StructuredResult
}

// JSON prompts (BYOK path) + tolerant JSON→DTO building. FM uses @Generable mirrors (macOS 26).
enum StructuredPrompt {
    static let system = """
    You are a precise bilingual assistant. Reply with ONLY a single JSON object, no markdown fences, no prose. \
    Leave a string as "" or an array as [] when a field does not apply — never output placeholder/empty entries.
    """

    static func user(kind: InputKind, source: String, firstLanguage: String, secondLanguage: String) -> String {
        let s = String(source.prefix(RefinePrompt.maxSourceChars))
        switch kind {
        case .word, .phrase:
            // Bilingual entry: "definition" in the SECOND language, "translation" = the meaning in the FIRST.
            return """
            For the term below, return a JSON dictionary entry. "definition" MUST be written in \(secondLanguage); \
            "translation" MUST be the meaning in \(firstLanguage); each example's "target" in \(firstLanguage):
            {"headword":"","pronunciation":"","senses":[{"partOfSpeech":"","definition":"(in \(secondLanguage))","translation":"(in \(firstLanguage))","examples":[{"source":"","target":"(in \(firstLanguage))"}],"synonyms":[""],"register":""}],"idioms":[{"phrase":"","meaning":"(in \(firstLanguage))"}]}
            Term: \(s)
            """
        case .sentence:
            // Only request fields the SentenceCard actually shows (dropped tokenGloss/clauses → smaller/faster).
            // For sentences: firstLanguage = the RESOLVED translation target; secondLanguage = the user's
            // NATIVE language, so grammar explanations stay readable even when translating OUT of it.
            return """
            Translate into \(firstLanguage) and analyze the sentence. Return JSON:
            {"refinedTranslation":"","syntax":{"subject":"","predicate":"","objects":[],"grammarPoints":[{"point":"","explanation":"(in \(secondLanguage))"}]},"notes":[]}
            Sentence: \(s)
            """
        }
    }
}

// Tolerant JSON → DTO builders (also a test target).
enum StructuredJSON {
    /// Return the FIRST balanced `{…}` span that parses as a JSON object — skipping brace-bearing prose or a
    /// preamble/thought object before the real answer (walks depth, respects string literals).
    static func object(from raw: String) -> [String: Any]? {
        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            guard chars[i] == "{" else { i += 1; continue }
            var depth = 0, inString = false, escaped = false, j = i, closed = false
            while j < chars.count {
                let c = chars[j]
                if inString {
                    if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                } else if c == "\"" { inString = true }
                else if c == "{" { depth += 1 }
                else if c == "}" { depth -= 1; if depth == 0 { closed = true; break } }
                j += 1
            }
            guard closed else { break }  // unbalanced from here on
            let slice = String(chars[i...j])
            if let obj = (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any] { return obj }
            i = j + 1  // this span wasn't a valid object → keep scanning
        }
        return nil
    }

    static func dictionary(from json: [String: Any]) -> DictionaryEntry {
        var e = DictionaryEntry()
        e.headword = json["headword"] as? String ?? ""
        e.pronunciation = json["pronunciation"] as? String ?? ""
        e.senses = (json["senses"] as? [[String: Any]] ?? []).map { s in
            var sense = Sense()
            sense.partOfSpeech = s["partOfSpeech"] as? String ?? ""
            sense.definition = s["definition"] as? String ?? ""
            sense.translation = s["translation"] as? String ?? ""
            sense.synonyms = (s["synonyms"] as? [String]) ?? []
            sense.register = s["register"] as? String ?? ""
            sense.examples = (s["examples"] as? [[String: Any]] ?? []).map {
                Example(source: $0["source"] as? String ?? "", target: $0["target"] as? String ?? "")
            }
            return sense
        }
        e.idioms = (json["idioms"] as? [[String: Any]] ?? []).map {
            Idiom(phrase: $0["phrase"] as? String ?? "", meaning: $0["meaning"] as? String ?? "")
        }
        return e
    }

    static func sentence(from json: [String: Any]) -> SentenceAnalysis {
        var a = SentenceAnalysis()
        a.refinedTranslation = json["refinedTranslation"] as? String ?? ""
        a.literalTranslation = json["literalTranslation"] as? String ?? ""
        a.notes = (json["notes"] as? [String]) ?? []
        if let syn = json["syntax"] as? [String: Any] {
            var b = SyntaxBreakdown()
            b.subject = syn["subject"] as? String ?? ""
            b.predicate = syn["predicate"] as? String ?? ""
            b.objects = (syn["objects"] as? [String]) ?? []
            b.clauses = (syn["clauses"] as? [[String: Any]] ?? []).map {
                Clause(text: $0["text"] as? String ?? "", role: $0["role"] as? String ?? "")
            }
            b.grammarPoints = (syn["grammarPoints"] as? [[String: Any]] ?? []).map {
                GrammarPoint(point: $0["point"] as? String ?? "", explanation: $0["explanation"] as? String ?? "")
            }
            b.tokenGloss = (syn["tokenGloss"] as? [[String: Any]] ?? []).map {
                Token(surface: $0["surface"] as? String ?? "", lemma: $0["lemma"] as? String ?? "",
                      pos: $0["pos"] as? String ?? "", gloss: $0["gloss"] as? String ?? "")
            }
            a.syntax = b
        }
        return a
    }
}
