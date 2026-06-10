import Foundation

// Input-aware output DTOs (PLAN §2.5). Plain Sendable structs (always compile on macOS 15); built
// tolerantly from BYOK JSON or from Foundation Models @Generable mirrors (macOS 26). Defaults make
// partial data safe to render.
enum InputKind: String, Sendable { case word, phrase, sentence }

struct DictionaryEntry: Sendable {
    var headword: String = ""
    var pronunciation: String = ""      // best-effort; may be empty (no clean Apple phonetic API)
    var senses: [Sense] = []
    var idioms: [Idiom] = []
    var isEmpty: Bool { senses.isEmpty && idioms.isEmpty }
}
struct Sense: Sendable {
    var partOfSpeech: String = ""
    var definition: String = ""
    var translation: String = ""
    var examples: [Example] = []
    var synonyms: [String] = []
    var register: String = ""
}
struct Example: Sendable { var source: String = ""; var target: String = "" }
struct Idiom: Sendable { var phrase: String = ""; var meaning: String = "" }

struct SentenceAnalysis: Sendable {
    var refinedTranslation: String = ""
    var literalTranslation: String = ""
    var syntax: SyntaxBreakdown = .init()
    var notes: [String] = []
    var isEmpty: Bool { refinedTranslation.isEmpty && syntax.isEmpty }
}
struct SyntaxBreakdown: Sendable {
    var clauses: [Clause] = []
    var subject: String = ""
    var predicate: String = ""
    var objects: [String] = []
    var grammarPoints: [GrammarPoint] = []
    var tokenGloss: [Token] = []
    var isEmpty: Bool {
        clauses.isEmpty && subject.isEmpty && predicate.isEmpty && grammarPoints.isEmpty && tokenGloss.isEmpty
    }
}
struct Clause: Sendable { var text: String = ""; var role: String = "" }
struct GrammarPoint: Sendable { var point: String = ""; var explanation: String = "" }
struct Token: Sendable { var surface: String = ""; var lemma: String = ""; var pos: String = ""; var gloss: String = "" }
