import Foundation
import XCTest
@testable import GlossPop

final class AnthropicSSEParserTests: XCTestCase {
    func testTextDelta() {
        let line = #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"你好"}}"#
        XCTAssertEqual(AnthropicSSE.parse(line: line), .delta("你好"))
    }

    func testThinkingDeltaIsIgnored() {
        let line = #"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hidden"}}"#
        XCTAssertEqual(AnthropicSSE.parse(line: line), .ignore)
    }

    func testMessageStopEndsStream() {
        XCTAssertEqual(AnthropicSSE.parse(line: #"data: {"type":"message_stop"}"#), .done)
        XCTAssertEqual(AnthropicSSE.parse(line: "data: [DONE]"), .done)
    }

    func testErrorFrameIncludesUpstreamMessage() {
        let line = #"data: {"type":"error","error":{"type":"rate_limit_error","message":"rate limited"}}"#
        XCTAssertEqual(AnthropicSSE.parse(line: line), .error("rate limited"))
    }

    func testLifecycleAndEventLinesAreIgnored() {
        XCTAssertEqual(AnthropicSSE.parse(line: "event: content_block_delta"), .ignore)
        XCTAssertEqual(AnthropicSSE.parse(line: #"data: {"type":"message_start"}"#), .ignore)
        XCTAssertEqual(AnthropicSSE.parse(line: #"data: {"type":"ping"}"#), .ignore)
        XCTAssertEqual(AnthropicSSE.parse(line: ": keep-alive"), .ignore)
    }
}

final class AnthropicCompatibleEngineTests: XCTestCase {
    func testRequestUsesAnthropicHeadersAndMovesSystemPromptToTopLevel() throws {
        let engine = anthropicEngine(host: "request.example.test", apiKey: "test-key")

        let request = try engine.makeRequest(
            messages: [
                ["role": "system", "content": "First system instruction"],
                ["role": "system", "content": "Second system instruction"],
                ["role": "user", "content": "Hello"],
                ["role": "assistant", "content": "Hi"],
                ["role": "tool", "content": "unsupported"],
            ],
            stream: true
        )

        XCTAssertEqual(request.url?.absoluteString, "https://request.example.test/apps/anthropic/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["max_tokens"] as? Int, 4096)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["system"] as? String, "First system instruction\n\nSecond system instruction")
        XCTAssertNil(body["reasoning_effort"])

        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [
            ["role": "user", "content": "Hello"],
            ["role": "assistant", "content": "Hi"],
        ])
    }

    func testEmptyAPIKeyDoesNotAddAuthenticationHeaders() throws {
        let request = try anthropicEngine(host: "no-key.example.test", apiKey: "")
            .makeRequest(messages: [["role": "user", "content": "Hello"]], stream: false)

        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testBearerRelayUsesAuthorizationInsteadOfXAPIKey() throws {
        let request = try anthropicEngine(
            host: "bearer-relay.example.test",
            apiKey: "relay-key",
            apiKeyHeader: .authorizationBearer
        ).makeRequest(messages: [["role": "user", "content": "Hello"]], stream: true)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer relay-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testRefineConsumesAnthropicStreamAndStopsAtMessageStop() async throws {
        let body = Data(
            """
            event: content_block_delta
            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"\u{4f60}"}}

            data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hidden"}}

            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"\u{597d}"}}

            data: {"type":"message_stop"}

            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ignored"}}

            """.utf8
        )
        let harness = anthropicHarness([.response(statusCode: 200, body: body)])
        defer { harness.close() }

        var snapshots: [String] = []
        for try await snapshot in harness.engine.refine(source: "hello", draft: "", targetCode: "zh-Hans") {
            snapshots.append(snapshot)
        }

        XCTAssertEqual(snapshots.last, "\u{4f60}\u{597d}")
        XCTAssertFalse(snapshots.contains(where: { $0.contains("ignored") }))
        XCTAssertEqual(harness.sequence.requestCount, 1)
    }

    func testStreamingClientErrorIncludesSanitizedDetail() async throws {
        let harness = anthropicHarness([
            .response(
                statusCode: 403,
                body: anthropicErrorResponse("permission denied; x-api-key=test-key")
            ),
        ])
        defer { harness.close() }

        do {
            for try await _ in harness.engine.refine(
                source: "hello",
                draft: "",
                targetCode: "zh-Hans"
            ) {}
            XCTFail("Expected the 403 response to fail")
        } catch let error as RefineError {
            guard case .http(let statusCode, let host, let detail) = error else {
                return XCTFail("Expected an HTTP error, got \(error)")
            }
            XCTAssertEqual(statusCode, 403)
            XCTAssertEqual(host, harness.host)
            XCTAssertEqual(detail, "permission denied; credential: ••••")
            XCTAssertFalse(error.localizedDescription.contains("test-key"))
        } catch {
            XCTFail("Expected RefineError.http, got \(error)")
        }
    }

    func testStreamingErrorFrameIsSanitized() async throws {
        let body = Data(
            (#"data: {"type":"error","error":{"message":"relay leaked sk-test-key"}}"# + "\n\n").utf8
        )
        let harness = anthropicHarness([.response(statusCode: 200, body: body)])
        defer { harness.close() }

        do {
            for try await _ in harness.engine.refine(
                source: "hello",
                draft: "",
                targetCode: "zh-Hans"
            ) {}
            XCTFail("Expected the stream error frame to fail")
        } catch let error as RefineError {
            guard case .message(let message) = error else {
                return XCTFail("Expected a message error, got \(error)")
            }
            XCTAssertFalse(message.contains("sk-test-key"))
            XCTAssertTrue(message.contains("••••"))
        } catch {
            XCTFail("Expected RefineError.message, got \(error)")
        }
    }

    func testStructuredResponseAggregatesTextBlocksAndIgnoresThinking() async throws {
        let harness = anthropicHarness([
            .response(statusCode: 200, body: anthropicValidDictionaryResponse()),
        ])
        defer { harness.close() }

        let result = try await anthropicDictionaryResult(from: harness.engine)

        anthropicAssertValidDictionary(result)
        XCTAssertEqual(harness.sequence.requestCount, 1)
    }

    func testStructuredClientErrorDoesNotRetry() async throws {
        let harness = anthropicHarness([
            .response(
                statusCode: 400,
                body: anthropicErrorResponse("unsupported parameter; x-api-key=test-key")
            ),
            .response(statusCode: 200, body: anthropicValidDictionaryResponse()),
        ])
        defer { harness.close() }

        do {
            _ = try await anthropicDictionaryResult(from: harness.engine)
            XCTFail("Expected the 400 response to fail")
        } catch let error as RefineError {
            guard case .http(let statusCode, let host, let detail) = error else {
                return XCTFail("Expected an HTTP error, got \(error)")
            }
            XCTAssertEqual(statusCode, 400)
            XCTAssertEqual(host, harness.host)
            XCTAssertEqual(detail, "unsupported parameter; credential: ••••")
        } catch {
            XCTFail("Expected RefineError.http, got \(error)")
        }

        XCTAssertEqual(harness.sequence.requestCount, 1)
    }

    func testStructuredServerErrorRetriesOnceAndKeepsLatestDetail() async throws {
        let harness = anthropicHarness([
            .response(statusCode: 500, body: anthropicErrorResponse("first failure")),
            .response(statusCode: 503, body: anthropicErrorResponse("second failure")),
        ])
        defer { harness.close() }

        do {
            _ = try await anthropicDictionaryResult(from: harness.engine)
            XCTFail("Expected both server responses to fail")
        } catch let error as RefineError {
            guard case .http(let statusCode, let host, let detail) = error else {
                return XCTFail("Expected an HTTP error, got \(error)")
            }
            XCTAssertEqual(statusCode, 503)
            XCTAssertEqual(host, harness.host)
            XCTAssertEqual(detail, "second failure")
        } catch {
            XCTFail("Expected RefineError.http, got \(error)")
        }

        XCTAssertEqual(harness.sequence.requestCount, 2)
    }

    func testStructuredServerErrorRetriesOnceThenSucceeds() async throws {
        let harness = anthropicHarness([
            .response(statusCode: 500, body: Data()),
            .response(statusCode: 200, body: anthropicValidDictionaryResponse()),
        ])
        defer { harness.close() }

        let result = try await anthropicDictionaryResult(from: harness.engine)

        anthropicAssertValidDictionary(result)
        XCTAssertEqual(harness.sequence.requestCount, 2)
    }

    func testStructuredMalformedResponseRetriesOnceThenSucceeds() async throws {
        let harness = anthropicHarness([
            .response(statusCode: 200, body: anthropicResponse(blocks: [["type": "text", "text": "not JSON"]])),
            .response(statusCode: 200, body: anthropicValidDictionaryResponse()),
        ])
        defer { harness.close() }

        let result = try await anthropicDictionaryResult(from: harness.engine)

        anthropicAssertValidDictionary(result)
        XCTAssertEqual(harness.sequence.requestCount, 2)
    }

    func testStructuredCancelledTransportDoesNotRetryAndThrowsCancellation() async throws {
        let harness = anthropicHarness([
            .failure(code: .cancelled),
            .response(statusCode: 200, body: anthropicValidDictionaryResponse()),
        ])
        defer { harness.close() }

        do {
            _ = try await anthropicDictionaryResult(from: harness.engine)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: transport cancellation preserves structured concurrency semantics.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(harness.sequence.requestCount, 1)
    }
}

private func anthropicEngine(
    host: String,
    apiKey: String,
    apiKeyHeader: BYOKAPIKeyHeader = .automatic
) -> AnthropicCompatibleEngine {
    let snapshot = BYOKSnapshot(
        baseURL: "https://\(host)",
        apiPath: "/apps/anthropic/v1/messages",
        apiFormat: .anthropic,
        apiKeyHeader: apiKeyHeader,
        model: "test-model",
        apiKey: apiKey,
        reasoningEffort: "high",
        customSystem: "",
        customUser: ""
    )
    return AnthropicCompatibleEngine(snapshot: snapshot)
}

private func anthropicDictionaryResult(from engine: AnthropicCompatibleEngine) async throws -> StructuredResult {
    try await engine.structured(
        kind: .word,
        source: "resilience",
        firstLanguage: "zh-Hans",
        secondLanguage: "en"
    )
}

private func anthropicAssertValidDictionary(
    _ result: StructuredResult,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .dictionary(let entry) = result else {
        return XCTFail("Expected a dictionary result", file: file, line: line)
    }
    XCTAssertEqual(entry.headword, "resilience", file: file, line: line)
    XCTAssertEqual(entry.senses.first?.translation, "韧性", file: file, line: line)
}

private struct AnthropicTransportHarness {
    let engine: AnthropicCompatibleEngine
    let session: URLSession
    let sequence: AnthropicResponseSequence
    let host: String

    func close() {
        AnthropicURLProtocol.unregister(host: host)
        session.invalidateAndCancel()
    }
}

private func anthropicHarness(_ steps: [AnthropicResponseStep]) -> AnthropicTransportHarness {
    let host = "\(UUID().uuidString.lowercased()).example.test"
    let sequence = AnthropicResponseSequence(steps)
    AnthropicURLProtocol.register(sequence, host: host)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AnthropicURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return AnthropicTransportHarness(
        engine: AnthropicCompatibleEngine(
            snapshot: BYOKSnapshot(
                baseURL: "https://\(host)",
                apiPath: "/apps/anthropic/v1/messages",
                apiFormat: .anthropic,
                model: "test-model",
                apiKey: "test-key",
                reasoningEffort: "default",
                customSystem: "",
                customUser: ""
            ),
            session: session
        ),
        session: session,
        sequence: sequence,
        host: host
    )
}

private enum AnthropicResponseStep: Sendable {
    case response(statusCode: Int, body: Data)
    case failure(code: URLError.Code)
}

private final class AnthropicResponseSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [AnthropicResponseStep]
    private var count = 0

    init(_ steps: [AnthropicResponseStep]) {
        self.steps = steps
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func next(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let step: AnthropicResponseStep
        lock.lock()
        count += 1
        if steps.isEmpty {
            lock.unlock()
            throw URLError(.resourceUnavailable)
        }
        step = steps.removeFirst()
        lock.unlock()

        switch step {
        case .response(let statusCode, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, body)
        case .failure(let code):
            throw URLError(code)
        }
    }
}

private final class AnthropicURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var sequences: [String: AnthropicResponseSequence] = [:]

    static func register(_ sequence: AnthropicResponseSequence, host: String) {
        registryLock.lock()
        sequences[host] = sequence
        registryLock.unlock()
    }

    static func unregister(host: String) {
        registryLock.lock()
        sequences.removeValue(forKey: host)
        registryLock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".example.test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.registryLock.lock()
        let sequence = Self.sequences[host]
        Self.registryLock.unlock()
        guard let sequence else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        do {
            let (response, data) = try sequence.next(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func anthropicResponse(blocks: [[String: Any]]) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "type": "message",
        "role": "assistant",
        "content": blocks,
    ])
}

private func anthropicErrorResponse(_ message: String) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "type": "error",
        "error": [
            "type": "request_error",
            "message": message,
        ],
    ])
}

private func anthropicValidDictionaryResponse() -> Data {
    anthropicResponse(blocks: [
        [
            "type": "text",
            "text": #"{"headword":"resilience","senses":["#,
        ],
        [
            "type": "thinking",
            "thinking": "This must not enter the structured JSON parser.",
        ],
        [
            "type": "text",
            "text": #"{"definition":"the ability to recover from difficulty","translation":"韧性"}],"idioms":[]}"#,
        ],
    ])
}
