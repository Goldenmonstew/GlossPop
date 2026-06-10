import XCTest
@testable import GlossPop

final class SSEParserTests: XCTestCase {
    func testDeltaContent() {
        let line = #"data: {"choices":[{"delta":{"content":"你好"}}]}"#
        XCTAssertEqual(SSE.parse(line: line), .delta("你好"))
    }

    func testNonStreamMessageContent() {
        let line = #"data: {"choices":[{"message":{"content":"ok"}}]}"#
        XCTAssertEqual(SSE.parse(line: line), .delta("ok"))
    }

    func testDoneSentinel() {
        XCTAssertEqual(SSE.parse(line: "data: [DONE]"), .done)
    }

    func testErrorFrameInsideStream() {
        let line = #"data: {"error":{"message":"rate limited"}}"#
        XCTAssertEqual(SSE.parse(line: line), .error("rate limited"))
    }

    func testNonDataLineIgnored() {
        XCTAssertEqual(SSE.parse(line: ": keep-alive"), .ignore)
        XCTAssertEqual(SSE.parse(line: ""), .ignore)
        XCTAssertEqual(SSE.parse(line: "event: message"), .ignore)
    }

    func testEmptyDeltaIgnored() {
        XCTAssertEqual(SSE.parse(line: #"data: {"choices":[{"delta":{"content":""}}]}"#), .ignore)
        XCTAssertEqual(SSE.parse(line: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#), .ignore)
    }
}
