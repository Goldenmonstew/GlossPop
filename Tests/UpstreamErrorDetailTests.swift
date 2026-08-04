import Foundation
import XCTest
@testable import GlossPop

final class UpstreamErrorDetailTests: XCTestCase {
    func testExtractsSupportedJSONErrorShapes() throws {
        let nested = try JSONSerialization.data(withJSONObject: [
            "error": ["message": "model is unavailable"],
        ])
        let topLevel = try JSONSerialization.data(withJSONObject: [
            "message": "permission denied",
        ])
        let stringError = try JSONSerialization.data(withJSONObject: [
            "error": "relay rejected the request",
        ])

        XCTAssertEqual(
            UpstreamErrorDetail.detail(from: nested, apiKey: "unused"),
            "model is unavailable"
        )
        XCTAssertEqual(
            UpstreamErrorDetail.detail(from: topLevel, apiKey: "unused"),
            "permission denied"
        )
        XCTAssertEqual(
            UpstreamErrorDetail.detail(from: stringError, apiKey: "unused"),
            "relay rejected the request"
        )
    }

    func testAllowsOnlyShortCompleteNonHTMLPlainText() {
        XCTAssertEqual(
            UpstreamErrorDetail.detail(
                from: Data("upstream route not found\ntry /v1/messages".utf8),
                apiKey: "unused"
            ),
            "upstream route not found try /v1/messages"
        )
        XCTAssertNil(
            UpstreamErrorDetail.detail(
                from: Data("<!doctype html><html><body>proxy error</body></html>".utf8),
                apiKey: "unused"
            )
        )
        XCTAssertNil(
            UpstreamErrorDetail.detail(from: Data([0x00, 0x01, 0x02]), apiKey: "unused")
        )
        XCTAssertNil(
            UpstreamErrorDetail.detail(
                from: Data(repeating: 0x61, count: UpstreamErrorDetail.maximumPlainTextBytes + 1),
                apiKey: "unused"
            )
        )
        XCTAssertNil(
            UpstreamErrorDetail.detail(
                from: Data(repeating: 0x61, count: UpstreamErrorDetail.maximumBodyBytes + 1),
                apiKey: "unused"
            )
        )
        XCTAssertNil(
            UpstreamErrorDetail.detail(
                from: Data(#"{"data":{"authorization":"Basic hidden"}}"#.utf8),
                apiKey: "unused"
            )
        )
    }

    func testSanitizesCredentialsControlsAndLength() {
        let exactKey = "test-secret-value"
        let raw = "denied\n\(exactKey) Authorization: Basic dGVzdA== x-api-key=header-secret access_token=relay-token client_secret=relay-secret Bearer x sk-example-secret"

        let detail = UpstreamErrorDetail.sanitized(raw, redacting: [exactKey])

        XCTAssertNotNil(detail)
        XCTAssertFalse(detail?.contains(exactKey) == true)
        XCTAssertFalse(detail?.contains("dGVzdA==") == true)
        XCTAssertFalse(detail?.contains("header-secret") == true)
        XCTAssertFalse(detail?.contains("relay-token") == true)
        XCTAssertFalse(detail?.contains("relay-secret") == true)
        XCTAssertFalse(detail?.contains("Bearer x") == true)
        XCTAssertFalse(detail?.contains("sk-example-secret") == true)
        XCTAssertFalse(detail?.contains("\n") == true)
        XCTAssertTrue(detail?.contains("••••") == true)

        let bounded = UpstreamErrorDetail.sanitized(String(repeating: "x", count: 400))
        XCTAssertEqual(bounded?.count, UpstreamErrorDetail.maximumDisplayCharacters)
        XCTAssertTrue(bounded?.hasSuffix("…") == true)
    }

    func testDoesNotRedactCredentialWordsWithoutAValue() {
        XCTAssertEqual(
            UpstreamErrorDetail.sanitized("API key invalid or missing"),
            "API key invalid or missing"
        )
    }

    func testHTTPErrorDescriptionKeepsStatusAndOptionalDetail() {
        XCTAssertEqual(
            RefineError.http(statusCode: 401, host: "api.example.com").localizedDescription,
            "HTTP 401 from api.example.com"
        )
        XCTAssertEqual(
            RefineError.http(
                statusCode: 404,
                host: "relay.example.com",
                detail: "route not found"
            ).localizedDescription,
            "HTTP 404 from relay.example.com — route not found"
        )
    }
}
