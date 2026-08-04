import Foundation

// BYOK refine through an Anthropic Messages-compatible endpoint. Anthropic keeps the system prompt at the
// top level and streams typed content-block deltas, so it needs a native adapter rather than OpenAI request
// or response emulation.
struct AnthropicCompatibleEngine: RefineEngine {
    let snapshot: BYOKSnapshot
    let session: URLSession

    init(snapshot: BYOKSnapshot, session: URLSession = .shared) {
        self.snapshot = snapshot
        self.session = session
    }

    var label: String { snapshot.label }
    var provenance: String { snapshot.provenance }
    func isAvailable() async -> Bool { true }

    func refine(source: String, draft: String, targetCode: String) -> AsyncThrowingStream<String, Error> {
        let engine = self
        return AsyncThrowingStream(String.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    let messages = RefinePrompt.messages(
                        source: source,
                        draft: draft,
                        targetCode: targetCode,
                        customSystem: engine.snapshot.customSystem,
                        customUser: engine.snapshot.customUser
                    )
                    let request = try engine.makeRequest(messages: messages, stream: true)
                    let (bytes, response) = try await engine.session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        let detail = try await UpstreamErrorDetail.detail(
                            from: bytes,
                            apiKey: engine.snapshot.apiKey
                        )
                        throw RefineError.http(
                            statusCode: http.statusCode,
                            host: engine.snapshot.host,
                            detail: detail
                        )
                    }

                    var accumulated = ""
                    streaming: for try await line in bytes.lines {
                        switch AnthropicSSE.parse(line: line) {
                        case .delta(let text):
                            accumulated += text
                            continuation.yield(accumulated)
                        case .done:
                            break streaming
                        case .error(let message):
                            throw RefineError.message(
                                UpstreamErrorDetail.sanitized(
                                    message,
                                    redacting: [engine.snapshot.apiKey]
                                ) ?? "upstream error"
                            )
                        case .ignore:
                            continue
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

    // Internal so request-shape tests can enforce the protocol boundary without sending network traffic.
    func makeRequest(messages: [[String: String]], stream: Bool) throws -> URLRequest {
        guard let url = snapshot.chatURL else {
            throw RefineError.invalidEndpoint(String(localized: "Invalid endpoint URL"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        BYOKAuthentication.apply(
            apiKey: snapshot.apiKey,
            format: snapshot.apiFormat,
            header: snapshot.apiKeyHeader,
            isLocal: snapshot.isLocal,
            to: &request
        )

        let system = messages.compactMap { message -> String? in
            guard message["role"] == "system" else { return nil }
            return message["content"]
        }.joined(separator: "\n\n")
        let turns = messages.compactMap { message -> [String: String]? in
            guard let role = message["role"],
                  role == "user" || role == "assistant",
                  let content = message["content"]
            else { return nil }
            return ["role": role, "content": content]
        }

        var body: [String: Any] = [
            "model": snapshot.model,
            "max_tokens": 4096,
            "stream": stream,
            "messages": turns,
        ]
        if !system.isEmpty { body["system"] = system }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

extension AnthropicCompatibleEngine: StructuredRefineEngine {
    func structured(
        kind: InputKind,
        source: String,
        firstLanguage: String,
        secondLanguage: String
    ) async throws -> StructuredResult {
        let messages = [
            ["role": "system", "content": StructuredPrompt.system],
            [
                "role": "user",
                "content": StructuredPrompt.user(
                    kind: kind,
                    source: source,
                    firstLanguage: firstLanguage,
                    secondLanguage: secondLanguage
                ),
            ],
        ]
        let request = try makeRequest(messages: messages, stream: false)

        // Match the existing OpenAI-compatible path: retry one transient network, 5xx, malformed JSON or
        // empty structured result, but never retry deterministic 4xx responses or cancellation.
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
                      let blocks = json["content"] as? [[String: Any]]
                else {
                    lastError = RefineError.malformedStructuredResponse
                    continue
                }
                let content = blocks.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }.joined()
                guard let object = StructuredJSON.object(from: content) else {
                    lastError = RefineError.malformedStructuredResponse
                    continue
                }

                switch kind {
                case .word, .phrase:
                    let entry = StructuredJSON.dictionary(from: object)
                    if entry.isEmpty {
                        lastError = RefineError.emptyStructuredResult
                        continue
                    }
                    return .dictionary(entry)
                case .sentence:
                    let analysis = StructuredJSON.sentence(from: object)
                    if analysis.isEmpty {
                        lastError = RefineError.emptyStructuredResult
                        continue
                    }
                    return .sentence(analysis)
                }
            } catch let error as RefineError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        try Task.checkCancellation()
        throw lastError
    }
}
