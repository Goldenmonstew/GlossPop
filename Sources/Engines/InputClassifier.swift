import Foundation
import NaturalLanguage

struct ClassifiedInput: Sendable {
    let kind: InputKind
    let source: Locale.Language
    let sourceCode: String
    let confident: Bool   // false for short/ambiguous text (fall back to instant + plain refine)
}

// Deterministic, on-device input classification (PLAN §2.5). Picks the output mode + detects source.
enum InputClassifier {
    static func classify(_ text: String) -> ClassifiedInput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let dominant = recognizer.dominantLanguage
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        let confident = dominant.map { $0 != .undetermined && (hypotheses[$0] ?? 0) >= 0.5 } ?? false
        let source = Locale.Language(identifier: (dominant ?? .undetermined).rawValue)

        var wordCount = 0
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { _, _ in wordCount += 1; return true }

        let hasSentencePunct = trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?。！？…；;\n")) != nil

        let kind: InputKind
        if wordCount <= 1 {
            kind = .word
        } else if !hasSentencePunct && !containsVerb(trimmed) && wordCount <= 4 {
            kind = .phrase
        } else {
            kind = .sentence
        }
        return ClassifiedInput(kind: kind, source: source, sourceCode: source.minimalIdentifier, confident: confident)
    }

    private static func containsVerb(_ text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var found = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if tag == .verb { found = true; return false }
            return true
        }
        return found
    }
}
