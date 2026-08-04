import Foundation
import XCTest
@testable import GlossPop

final class BYOKAuthenticationTests: XCTestCase {
    func testAuthenticationMatrixUsesExactlyTheSelectedHeader() throws {
        struct Case {
            let name: String
            let format: BYOKAPIFormat
            let header: BYOKAPIKeyHeader
            let isLocal: Bool
            let apiKey: String
            let authorization: String?
            let xAPIKey: String?
        }

        let cases = [
            Case(
                name: "automatic OpenAI cloud",
                format: .openAI,
                header: .automatic,
                isLocal: false,
                apiKey: "openai-key",
                authorization: "Bearer openai-key",
                xAPIKey: nil
            ),
            Case(
                name: "automatic Anthropic cloud",
                format: .anthropic,
                header: .automatic,
                isLocal: false,
                apiKey: "anthropic-key",
                authorization: nil,
                xAPIKey: "anthropic-key"
            ),
            Case(
                name: "Bearer Anthropic relay",
                format: .anthropic,
                header: .authorizationBearer,
                isLocal: false,
                apiKey: "relay-key",
                authorization: "Bearer relay-key",
                xAPIKey: nil
            ),
            Case(
                name: "x-api-key OpenAI relay",
                format: .openAI,
                header: .xAPIKey,
                isLocal: false,
                apiKey: "relay-key",
                authorization: nil,
                xAPIKey: "relay-key"
            ),
            Case(
                name: "explicit no authentication",
                format: .anthropic,
                header: .none,
                isLocal: false,
                apiKey: "unused-key",
                authorization: nil,
                xAPIKey: nil
            ),
            Case(
                name: "automatic loopback does not leak a cloud key",
                format: .openAI,
                header: .automatic,
                isLocal: true,
                apiKey: "cloud-key",
                authorization: nil,
                xAPIKey: nil
            ),
            Case(
                name: "empty key",
                format: .anthropic,
                header: .xAPIKey,
                isLocal: false,
                apiKey: "",
                authorization: nil,
                xAPIKey: nil
            ),
        ]

        for item in cases {
            var request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.test/v1/messages")))
            request.setValue("stale-bearer", forHTTPHeaderField: "Authorization")
            request.setValue("stale-x-api-key", forHTTPHeaderField: "x-api-key")

            BYOKAuthentication.apply(
                apiKey: item.apiKey,
                format: item.format,
                header: item.header,
                isLocal: item.isLocal,
                to: &request
            )

            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                item.authorization,
                item.name
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "x-api-key"),
                item.xAPIKey,
                item.name
            )
        }
    }

    func testExplicitAuthenticationCanBeUsedByALoopbackRelay() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:8080/v1/messages")))

        BYOKAuthentication.apply(
            apiKey: "local-relay-key",
            format: .anthropic,
            header: .authorizationBearer,
            isLocal: true,
            to: &request
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-relay-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
    }
}
