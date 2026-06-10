import Foundation

// BYOK refine via any OpenAI-compatible /v1/chat/completions endpoint: cloud, 中转 relay, or local
// Ollama/LM Studio (PLAN §4). Streams SSE deltas, yielding cumulative snapshots. Holds an immutable
// BYOKSnapshot so the request + provenance stay consistent even if settings change mid-stream.
struct OpenAICompatibleEngine: RefineEngine {
    let snapshot: BYOKSnapshot

    var label: String { snapshot.label }
    var provenance: String { snapshot.provenance }
    func isAvailable() async -> Bool { true } // constructed only from a ready snapshot

    func refine(source: String, draft: String, targetCode: String) -> AsyncThrowingStream<String, Error> {
        let snapshot = self.snapshot
        // Cumulative snapshots → safe to drop intermediate frames if the UI can't keep up.
        return AsyncThrowingStream(String.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    guard let url = snapshot.chatURL else {
                        throw RefineError.message(String(localized: "Invalid endpoint URL (needs http(s) and a host)"))
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60 // idle timeout — a stalled relay can't hang the card forever
                    if !snapshot.apiKey.isEmpty {
                        request.setValue("Bearer \(snapshot.apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    var body: [String: Any] = [
                        "model": snapshot.model,
                        "stream": true,
                        "max_tokens": 4096, // headroom for reasoning models + the translation
                        "messages": RefinePrompt.messages(source: source, draft: draft, targetCode: targetCode,
                                                          customSystem: snapshot.customSystem, customUser: snapshot.customUser),
                    ]
                    if snapshot.reasoningEffort != "default" { body["reasoning_effort"] = snapshot.reasoningEffort }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw RefineError.message("HTTP \(http.statusCode) from \(snapshot.host)")
                    }

                    var accumulated = ""
                    streaming: for try await line in bytes.lines {
                        switch SSE.parse(line: line) {
                        case .delta(let text): accumulated += text; continuation.yield(accumulated)
                        case .done: break streaming
                        case .error(let message): throw RefineError.message(message)
                        case .ignore: continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum RefineError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}
