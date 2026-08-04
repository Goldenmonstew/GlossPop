import Foundation

// BYOK refine via any OpenAI-compatible /v1/chat/completions endpoint: cloud, 中转 relay, or local
// Ollama/LM Studio (PLAN §4). Streams SSE deltas, yielding cumulative snapshots. Holds an immutable
// BYOKSnapshot so the request + provenance stay consistent even if settings change mid-stream.
struct OpenAICompatibleEngine: RefineEngine {
    let snapshot: BYOKSnapshot
    let session: URLSession

    init(snapshot: BYOKSnapshot, session: URLSession = .shared) {
        self.snapshot = snapshot
        self.session = session
    }

    var label: String { snapshot.label }
    var provenance: String { snapshot.provenance }
    func isAvailable() async -> Bool { true } // constructed only from a ready snapshot

    func refine(source: String, draft: String, targetCode: String) -> AsyncThrowingStream<String, Error> {
        let snapshot = self.snapshot
        let session = self.session
        // Cumulative snapshots → safe to drop intermediate frames if the UI can't keep up.
        return AsyncThrowingStream(String.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    guard let url = snapshot.chatURL else {
                        throw RefineError.invalidEndpoint(
                            String(localized: "Invalid endpoint URL (needs http(s) and a host)")
                        )
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60 // idle timeout — a stalled relay can't hang the card forever
                    BYOKAuthentication.apply(
                        apiKey: snapshot.apiKey,
                        format: snapshot.apiFormat,
                        header: snapshot.apiKeyHeader,
                        isLocal: snapshot.isLocal,
                        to: &request
                    )
                    var body: [String: Any] = [
                        "model": snapshot.model,
                        "stream": true,
                        "max_tokens": 4096, // headroom for reasoning models + the translation
                        "messages": RefinePrompt.messages(source: source, draft: draft, targetCode: targetCode,
                                                          customSystem: snapshot.customSystem, customUser: snapshot.customUser),
                    ]
                    if snapshot.reasoningEffort != "default" { body["reasoning_effort"] = snapshot.reasoningEffort }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        let detail = try await UpstreamErrorDetail.detail(
                            from: bytes,
                            apiKey: snapshot.apiKey
                        )
                        throw RefineError.http(
                            statusCode: http.statusCode,
                            host: snapshot.host,
                            detail: detail
                        )
                    }

                    var accumulated = ""
                    streaming: for try await line in bytes.lines {
                        switch SSE.parse(line: line) {
                        case .delta(let text): accumulated += text; continuation.yield(accumulated)
                        case .done: break streaming
                        case .error(let message):
                            throw RefineError.message(
                                UpstreamErrorDetail.sanitized(
                                    message,
                                    redacting: [snapshot.apiKey]
                                ) ?? "upstream error"
                            )
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
    case invalidEndpoint(String)
    case http(statusCode: Int, host: String, detail: String? = nil)
    case malformedStructuredResponse
    case emptyStructuredResult

    var errorDescription: String? {
        switch self {
        case .message(let message), .invalidEndpoint(let message):
            return message
        case .http(let statusCode, let host, let detail):
            let summary = "HTTP \(statusCode) from \(host)"
            return detail.map { "\(summary) — \($0)" } ?? summary
        case .malformedStructuredResponse:
            return String(localized: "Couldn't parse the structured response")
        case .emptyStructuredResult:
            return String(localized: "Empty structured result")
        }
    }
}
