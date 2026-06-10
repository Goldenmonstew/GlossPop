import Foundation

// BYOK structured output (PLAN §2.5): a non-streaming chat completion asking for JSON, parsed tolerantly
// into a DictionaryEntry / SentenceAnalysis. No response_format (many relays reject it) — the prompt forces
// JSON and StructuredJSON.object() tolerates fences/prose.
extension OpenAICompatibleEngine: StructuredRefineEngine {
    func structured(kind: InputKind, source: String, firstLanguage: String, secondLanguage: String) async throws -> StructuredResult {
        guard let url = snapshot.chatURL else { throw RefineError.message(String(localized: "Invalid endpoint URL")) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !snapshot.apiKey.isEmpty {
            request.setValue("Bearer \(snapshot.apiKey)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = [
            "model": snapshot.model,
            "stream": false,
            "max_tokens": 4096,
            "messages": [
                ["role": "system", "content": StructuredPrompt.system],
                ["role": "user", "content": StructuredPrompt.user(kind: kind, source: source, firstLanguage: firstLanguage, secondLanguage: secondLanguage)],
            ],
        ]
        if snapshot.reasoningEffort != "default" { body["reasoning_effort"] = snapshot.reasoningEffort }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw RefineError.message("HTTP \(code) from \(snapshot.host)") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let content = (choices.first?["message"] as? [String: Any])?["content"] as? String,
              let object = StructuredJSON.object(from: content) else {
            throw RefineError.message(String(localized: "Couldn't parse the structured response"))
        }
        switch kind {
        case .word, .phrase:
            let entry = StructuredJSON.dictionary(from: object)
            guard !entry.isEmpty else { throw RefineError.message(String(localized: "Empty structured result")) } // → caller falls back to plain refine
            return .dictionary(entry)
        case .sentence:
            let analysis = StructuredJSON.sentence(from: object)
            guard !analysis.isEmpty else { throw RefineError.message(String(localized: "Empty structured result")) }
            return .sentence(analysis)
        }
    }
}
