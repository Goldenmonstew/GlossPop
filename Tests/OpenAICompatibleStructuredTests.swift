import Foundation
import XCTest
@testable import GlossPop

final class OpenAICompatibleStructuredTests: XCTestCase {
    func testClientErrorDoesNotRetry() async throws {
        let harness = makeHarness([
            .response(statusCode: 400, body: completionData(content: #"{"error":"bad request"}"#)),
        ])
        defer { harness.close() }

        do {
            _ = try await dictionaryResult(from: harness.engine)
            XCTFail("Expected the 400 response to fail")
        } catch let error as RefineError {
            guard case .http(let statusCode, let host) = error else {
                return XCTFail("Expected an HTTP error, got \(error)")
            }
            XCTAssertEqual(statusCode, 400)
            XCTAssertEqual(host, harness.host)
        } catch {
            XCTFail("Expected RefineError.http, got \(error)")
        }

        XCTAssertEqual(harness.sequence.requestCount, 1)
    }

    func testServerErrorRetriesOnceThenSucceeds() async throws {
        let harness = makeHarness([
            .response(statusCode: 500, body: Data()),
            .response(statusCode: 200, body: validDictionaryCompletion()),
        ])
        defer { harness.close() }

        let result = try await dictionaryResult(from: harness.engine)

        assertValidDictionary(result)
        XCTAssertEqual(harness.sequence.requestCount, 2)
    }

    func testMalformedResponseRetriesOnceThenSucceeds() async throws {
        let harness = makeHarness([
            .response(statusCode: 200, body: completionData(content: "not JSON")),
            .response(statusCode: 200, body: validDictionaryCompletion()),
        ])
        defer { harness.close() }

        let result = try await dictionaryResult(from: harness.engine)

        assertValidDictionary(result)
        XCTAssertEqual(harness.sequence.requestCount, 2)
    }

    func testEmptyStructuredResultRetriesOnceThenSucceeds() async throws {
        let harness = makeHarness([
            .response(statusCode: 200, body: completionData(content: "{}")),
            .response(statusCode: 200, body: validDictionaryCompletion()),
        ])
        defer { harness.close() }

        let result = try await dictionaryResult(from: harness.engine)

        assertValidDictionary(result)
        XCTAssertEqual(harness.sequence.requestCount, 2)
    }

    func testCancelledTransportDoesNotRetryAndThrowsCancellation() async throws {
        let harness = makeHarness([
            .failure(code: .cancelled),
            .response(statusCode: 200, body: validDictionaryCompletion()),
        ])
        defer { harness.close() }

        do {
            _ = try await dictionaryResult(from: harness.engine)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: transport cancellation preserves structured concurrency semantics.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(harness.sequence.requestCount, 1)
    }

    private func dictionaryResult(from engine: OpenAICompatibleEngine) async throws -> StructuredResult {
        try await engine.structured(
            kind: .word,
            source: "resilience",
            firstLanguage: "zh-Hans",
            secondLanguage: "en"
        )
    }

    private func assertValidDictionary(
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
}

private struct StructuredTransportHarness {
    let engine: OpenAICompatibleEngine
    let session: URLSession
    let sequence: StructuredResponseSequence
    let host: String

    func close() {
        StructuredURLProtocol.unregister(host: host)
        session.invalidateAndCancel()
    }
}

private func makeHarness(_ steps: [StructuredResponseStep]) -> StructuredTransportHarness {
    let host = "\(UUID().uuidString.lowercased()).example.test"
    let sequence = StructuredResponseSequence(steps)
    StructuredURLProtocol.register(sequence, host: host)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StructuredURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let snapshot = BYOKSnapshot(
        baseURL: "https://\(host)",
        apiPath: "/v1/chat/completions",
        model: "test-model",
        apiKey: "test-key",
        reasoningEffort: "default",
        customSystem: "",
        customUser: ""
    )
    return StructuredTransportHarness(
        engine: OpenAICompatibleEngine(snapshot: snapshot, session: session),
        session: session,
        sequence: sequence,
        host: host
    )
}

private enum StructuredResponseStep: Sendable {
    case response(statusCode: Int, body: Data)
    case failure(code: URLError.Code)
}

private final class StructuredResponseSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [StructuredResponseStep]
    private var count = 0

    init(_ steps: [StructuredResponseStep]) {
        self.steps = steps
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func next(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let step: StructuredResponseStep
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

private final class StructuredURLProtocol: URLProtocol, @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var sequences: [String: StructuredResponseSequence] = [:]

    static func register(_ sequence: StructuredResponseSequence, host: String) {
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

private func completionData(content: String) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "choices": [
            ["message": ["content": content]],
        ],
    ])
}

private func validDictionaryCompletion() -> Data {
    completionData(
        content: """
        {
          "headword": "resilience",
          "senses": [
            {
              "definition": "the ability to recover from difficulty",
              "translation": "韧性"
            }
          ],
          "idioms": []
        }
        """
    )
}
