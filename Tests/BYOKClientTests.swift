import Foundation
import XCTest
@testable import GlossPop

final class BYOKClientTests: XCTestCase {
    func testAnthropicModelsRequestUsesSiblingURLAndNativeHeaders() async throws {
        let harness = makeBYOKClientHarness(
            body: #"{"data":[{"id":"claude-sonnet"},{"id":"claude-haiku"}]}"#.data(using: .utf8)!
        )
        defer { harness.close() }

        let models = try await BYOKClient.models(
            baseURL: "https://\(harness.host)",
            apiPath: "/apps/anthropic/v1/messages?workspace=test",
            apiFormat: .anthropic,
            apiKeyHeader: .automatic,
            apiKey: "anthropic-key",
            session: harness.session
        )

        XCTAssertEqual(models, ["claude-haiku", "claude-sonnet"])
        let request = try XCTUnwrap(harness.probe.lastRequest)
        XCTAssertEqual(request.httpMethod ?? "GET", "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://\(harness.host)/apps/anthropic/v1/models?workspace=test"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testAnthropicBearerRelayUsesAuthorizationForModelDiscovery() async throws {
        let harness = makeBYOKClientHarness(body: #"{"data":[{"id":"relay-model"}]}"#.data(using: .utf8)!)
        defer { harness.close() }
        let folded = BYOKConfig.fold(
            base: "https://\(harness.host)/claude/v1/messages",
            path: "/v1/messages"
        )

        let models = try await BYOKClient.models(
            baseURL: folded.base,
            apiPath: folded.path,
            apiFormat: .anthropic,
            apiKeyHeader: .authorizationBearer,
            apiKey: "relay-key",
            session: harness.session
        )

        XCTAssertEqual(models, ["relay-model"])
        let request = try XCTUnwrap(harness.probe.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://\(harness.host)/claude/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer relay-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testOpenAIModelsRequestKeepsBearerDefaultAndOmitsAnthropicVersion() async throws {
        let harness = makeBYOKClientHarness(body: #"{"data":[{"id":"z-model"},{"id":"a-model"}]}"#.data(using: .utf8)!)
        defer { harness.close() }

        let models = try await BYOKClient.models(
            baseURL: "https://\(harness.host)",
            apiPath: "/compatible-mode/v1/chat/completions",
            apiFormat: .openAI,
            apiKeyHeader: .automatic,
            apiKey: "openai-key",
            session: harness.session
        )

        XCTAssertEqual(models, ["a-model", "z-model"])
        let request = try XCTUnwrap(harness.probe.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://\(harness.host)/compatible-mode/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openai-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-version"))
    }

    func testModelDiscoveryHTTPErrorPreservesStatusHostAndSanitizedDetail() async throws {
        let harness = makeBYOKClientHarness(
            statusCode: 404,
            body: Data(#"{"message":"route missing for Bearer relay-key"}"#.utf8)
        )
        defer { harness.close() }

        do {
            _ = try await BYOKClient.models(
                baseURL: "https://\(harness.host)",
                apiPath: "/v1/messages",
                apiFormat: .anthropic,
                apiKeyHeader: .authorizationBearer,
                apiKey: "relay-key",
                session: harness.session
            )
            XCTFail("Expected model discovery to fail")
        } catch let error as RefineError {
            guard case .http(let statusCode, let host, let detail) = error else {
                return XCTFail("Expected an HTTP error, got \(error)")
            }
            XCTAssertEqual(statusCode, 404)
            XCTAssertEqual(host, harness.host)
            XCTAssertEqual(detail, "route missing for Bearer ••••")
            XCTAssertFalse(error.localizedDescription.contains("relay-key"))
        } catch {
            XCTFail("Expected RefineError.http, got \(error)")
        }
    }
}

private struct BYOKClientHarness {
    let host: String
    let probe: BYOKClientProbe
    let session: URLSession

    func close() {
        BYOKClientURLProtocol.unregister(host: host)
        session.invalidateAndCancel()
    }
}

private func makeBYOKClientHarness(statusCode: Int = 200, body: Data) -> BYOKClientHarness {
    let host = "\(UUID().uuidString.lowercased()).example.test"
    let probe = BYOKClientProbe(statusCode: statusCode, body: body)
    BYOKClientURLProtocol.register(probe, host: host)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BYOKClientURLProtocol.self]
    return BYOKClientHarness(
        host: host,
        probe: probe,
        session: URLSession(configuration: configuration)
    )
}

private final class BYOKClientProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let statusCode: Int
    private let body: Data
    private var capturedRequest: URLRequest?

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequest
    }

    func response(for request: URLRequest) -> (HTTPURLResponse, Data) {
        lock.lock()
        capturedRequest = request
        lock.unlock()
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!,
            body
        )
    }
}

private final class BYOKClientURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var probes: [String: BYOKClientProbe] = [:]

    static func register(_ probe: BYOKClientProbe, host: String) {
        lock.lock()
        probes[host] = probe
        lock.unlock()
    }

    static func unregister(host: String) {
        lock.lock()
        probes.removeValue(forKey: host)
        lock.unlock()
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
        Self.lock.lock()
        let probe = Self.probes[host]
        Self.lock.unlock()
        guard let probe else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        let (response, data) = probe.response(for: request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
