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

        // One retry: a malformed-JSON / empty / 5xx / network response is usually non-deterministic and
        // clears on a resample (eval saw some models fail JSON ~10% of the time). A 4xx is deterministic —
        // propagate it without retrying.
        var lastMessage = String(localized: "Couldn't parse the structured response")
        for _ in 0..<2 {
            if Task.isCancelled { break }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                if (400..<500).contains(code) { throw RefineError.message("HTTP \(code) from \(snapshot.host)") }
                guard (200..<300).contains(code) else { lastMessage = "HTTP \(code) from \(snapshot.host)"; continue }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let content = (choices.first?["message"] as? [String: Any])?["content"] as? String,
                      let object = StructuredJSON.object(from: content) else {
                    lastMessage = String(localized: "Couldn't parse the structured response"); continue
                }
                switch kind {
                case .word, .phrase:
                    let entry = StructuredJSON.dictionary(from: object)
                    if entry.isEmpty { lastMessage = String(localized: "Empty structured result"); continue } // → caller falls back to plain refine
                    return .dictionary(entry)
                case .sentence:
                    let analysis = StructuredJSON.sentence(from: object)
                    if analysis.isEmpty { lastMessage = String(localized: "Empty structured result"); continue }
                    return .sentence(analysis)
                }
            } catch let e as RefineError {
                throw e   // deterministic client error — no retry
            } catch {
                lastMessage = error.localizedDescription   // transient network blip — retry once
            }
        }
        throw RefineError.message(lastMessage)
    }
}
