import Foundation

// BYOK structured output (PLAN §2.5): a non-streaming chat completion asking for JSON, parsed tolerantly
// into a DictionaryEntry / SentenceAnalysis. No response_format (many relays reject it) — the prompt forces
// JSON and StructuredJSON.object() tolerates fences/prose.
extension OpenAICompatibleEngine: StructuredRefineEngine {
    func structured(kind: InputKind, source: String, firstLanguage: String, secondLanguage: String) async throws -> StructuredResult {
        guard let url = snapshot.chatURL else {
            throw RefineError.invalidEndpoint(String(localized: "Invalid endpoint URL"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        BYOKAuthentication.apply(
            apiKey: snapshot.apiKey,
            format: snapshot.apiFormat,
            header: snapshot.apiKeyHeader,
            isLocal: snapshot.isLocal,
            to: &request
        )
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
        var lastError: any Error = RefineError.malformedStructuredResponse
        for _ in 0..<2 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                if (400..<500).contains(code) {
                    throw RefineError.http(
                        statusCode: code,
                        host: snapshot.host,
                        detail: UpstreamErrorDetail.detail(from: data, apiKey: snapshot.apiKey)
                    )
                }
                guard (200..<300).contains(code) else {
                    lastError = RefineError.http(
                        statusCode: code,
                        host: snapshot.host,
                        detail: UpstreamErrorDetail.detail(from: data, apiKey: snapshot.apiKey)
                    )
                    continue
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let content = (choices.first?["message"] as? [String: Any])?["content"] as? String,
                      let object = StructuredJSON.object(from: content) else {
                    lastError = RefineError.malformedStructuredResponse
                    continue
                }
                switch kind {
                case .word, .phrase:
                    let entry = StructuredJSON.dictionary(from: object)
                    if entry.isEmpty {
                        lastError = RefineError.emptyStructuredResult
                        continue
                    } // → caller falls back to plain refine
                    return .dictionary(entry)
                case .sentence:
                    let analysis = StructuredJSON.sentence(from: object)
                    if analysis.isEmpty {
                        lastError = RefineError.emptyStructuredResult
                        continue
                    }
                    return .sentence(analysis)
                }
            } catch let e as RefineError {
                throw e   // deterministic client error — no retry
            } catch is CancellationError {
                throw CancellationError()
            } catch let e as URLError where e.code == .cancelled {
                throw CancellationError()
            } catch {
                lastError = error   // transient network blip — retry once
            }
        }
        try Task.checkCancellation()
        throw lastError
    }
}
