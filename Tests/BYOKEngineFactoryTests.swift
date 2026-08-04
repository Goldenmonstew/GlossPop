import XCTest
@testable import GlossPop

final class BYOKEngineFactoryTests: XCTestCase {
    func testOpenAIFormatBuildsOpenAICompatibleEngine() {
        let snapshot = makeSnapshot(format: .openAI)

        let engine = BYOKEngineFactory.make(snapshot: snapshot)

        XCTAssertTrue(engine is OpenAICompatibleEngine)
        XCTAssertEqual((engine as? OpenAICompatibleEngine)?.snapshot.apiFormat, .openAI)
    }

    func testAnthropicFormatBuildsAnthropicCompatibleEngine() {
        let snapshot = makeSnapshot(format: .anthropic)

        let engine = BYOKEngineFactory.make(snapshot: snapshot)

        XCTAssertTrue(engine is AnthropicCompatibleEngine)
        XCTAssertEqual((engine as? AnthropicCompatibleEngine)?.snapshot.apiFormat, .anthropic)
    }

    private func makeSnapshot(format: BYOKAPIFormat) -> BYOKSnapshot {
        BYOKSnapshot(
            baseURL: "https://api.example.com",
            apiPath: format == .openAI ? "/v1/chat/completions" : "/v1/messages",
            apiFormat: format,
            model: "example-model",
            apiKey: "secret",
            reasoningEffort: "default",
            customSystem: "",
            customUser: ""
        )
    }
}
