import Foundation

// LLM translation engine: streams CUMULATIVE snapshots (each value is the full text-so-far) into the
// card. `draft` is empty for a plain translation; a non-empty draft would ask the model to improve it.
// Non-@MainActor so the network/LLM work runs off the main actor; consumed back on the main actor.
protocol RefineEngine: Sendable {
    var label: String { get }                       // e.g. "端上 LLM" / "云 · api.deepseek.com"
    var provenance: String { get }                  // privacy note shown after refine (端上/本机/云·host)
    func isAvailable() async -> Bool
    func refine(source: String, draft: String, targetCode: String) -> AsyncThrowingStream<String, Error>
}

// Shared prompt for plain-text refine (M3b). Input-aware structured prompts arrive in M3.5.
enum RefinePrompt {
    static let maxSourceChars = 4000 // cap so a whole-page selection can't blow context / cost / privacy

    static let system = """
    You are a professional translator. Improve the draft translation so it is accurate, natural, and \
    idiomatic in the target language. Output ONLY the improved translation — no notes, no quotes, no labels.
    """
    static func user(source rawSource: String, draft rawDraft: String, targetCode: String) -> String {
        let source = String(rawSource.prefix(maxSourceChars))
        let draft = String(rawDraft.prefix(maxSourceChars))
        // Empty draft → translate directly (the normal path); non-empty draft → improve it.
        if draft.isEmpty {
            return """
            Translate the following text into \(targetCode). Output ONLY the translation.

            \(source)
            """
        }
        return """
        Target language: \(targetCode)

        Source:
        \(source)

        Draft translation:
        \(draft)

        Improved translation:
        """
    }

    /// Chat messages: a user-supplied custom prompt (with $text / $target substituted) if provided,
    /// else the built-in translation prompt.
    static func messages(source: String, draft: String, targetCode: String,
                         customSystem: String, customUser: String) -> [[String: String]] {
        // Blank-aware: a whitespace-only custom prompt must fall back to the built-in one.
        let ws = CharacterSet.whitespacesAndNewlines
        let sysBlank = customSystem.trimmingCharacters(in: ws).isEmpty
        let usrBlank = customUser.trimmingCharacters(in: ws).isEmpty
        guard !sysBlank || !usrBlank else {
            return [["role": "system", "content": system],
                    ["role": "user", "content": user(source: source, draft: draft, targetCode: targetCode)]]
        }
        let cappedSource = String(source.prefix(maxSourceChars))
        func sub(_ t: String) -> String {
            // $target BEFORE $text so a literal "$target" inside the source isn't rewritten.
            let expanded = String(t.prefix(8000))
                .replacingOccurrences(of: "$target", with: targetCode)
                .replacingOccurrences(of: "$text", with: cappedSource)
            return String(expanded.prefix(maxSourceChars + 4000)) // cap the EXPANDED result, not just the template (P2)
        }
        var msgs: [[String: String]] = []
        if !sysBlank { msgs.append(["role": "system", "content": sub(customSystem)]) }
        msgs.append(["role": "user", "content": usrBlank ? cappedSource : sub(customUser)])
        return msgs
    }
}
