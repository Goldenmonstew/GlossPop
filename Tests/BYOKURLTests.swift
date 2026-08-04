import XCTest
@testable import GlossPop

final class BYOKURLTests: XCTestCase {
    func testChatURLHostPlusStandardPath() {
        let u = BYOKConfig.chatURL(base: "https://api.openai.com", path: "/v1/chat/completions")
        XCTAssertEqual(u?.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testChatURLRelayNonStandardPath() {
        // The user's relay: host base + a non-standard /aigc/v1 path must rebuild the working URL.
        let u = BYOKConfig.chatURL(base: "https://relay.example.com", path: "/aigc/v1/chat/completions")
        XCTAssertEqual(u?.absoluteString, "https://relay.example.com/aigc/v1/chat/completions")
    }

    func testModelsURLDerivedFromChatPath() {
        let u = BYOKConfig.modelsURL(base: "https://relay.example.com", path: "/aigc/v1/chat/completions")
        XCTAssertEqual(u?.absoluteString, "https://relay.example.com/aigc/v1/models")
    }

    func testModelsURLDerivedFromAnthropicMessagesPath() {
        let u = BYOKConfig.modelsURL(
            base: "https://relay.example.com",
            path: "/apps/anthropic/v1/messages"
        )
        XCTAssertEqual(u?.absoluteString, "https://relay.example.com/apps/anthropic/v1/models")
    }

    func testModelsURLAcceptsACompleteAnthropicRequestURL() {
        let u = BYOKConfig.modelsURL(
            base: "https://relay.example.com/apps/anthropic/v1/messages",
            path: "/v1/messages"
        )
        XCTAssertEqual(u?.absoluteString, "https://relay.example.com/apps/anthropic/v1/models")
    }

    func testModelsURLFallbackWhenPathHasNoChatCompletions() {
        let u = BYOKConfig.modelsURL(base: "https://api.openai.com", path: "/custom")
        XCTAssertEqual(u?.absoluteString, "https://api.openai.com/v1/models")
    }

    func testChatURLEmptyBaseIsNil() {
        XCTAssertNil(BYOKConfig.chatURL(base: "", path: "/v1/chat/completions"))
    }

    func testChatURLSchemelessHostGetsHTTPS() {
        // url() normalizes a scheme-less host by prepending https:// (existing behavior).
        let u = BYOKConfig.chatURL(base: "myrelay.example.com", path: "/v1/chat/completions")
        XCTAssertEqual(u?.absoluteString, "https://myrelay.example.com/v1/chat/completions")
    }

    func testApiPathCannotRedirectToAnotherHost() {
        // A path that's secretly a full URL must NOT redirect the request off the configured host.
        let u = BYOKConfig.chatURL(base: "https://safe.example.com", path: "https://evil.example/v1/chat/completions")
        XCTAssertEqual(u?.host, "safe.example.com")
        XCTAssertEqual(u?.absoluteString, "https://safe.example.com/v1/chat/completions")
    }

    func testModelsURLOnlyRewritesChatCompletionsSuffix() {
        // "/chat/completions" as a non-suffix must not be naively rewritten → fall back to /v1/models.
        let u = BYOKConfig.modelsURL(base: "https://api.openai.com", path: "/v1/chat/completions/extra")
        XCTAssertEqual(u?.absoluteString, "https://api.openai.com/v1/models")
    }

    func testSanitizedPathAddsLeadingSlash() {
        XCTAssertEqual(BYOKConfig.sanitizedPath("v1/chat/completions").path, "/v1/chat/completions")
        XCTAssertEqual(BYOKConfig.sanitizedPath("").path, "/v1/chat/completions")
    }

    func testHostOnlyFoldsBasePath() {
        let split = BYOKConfig.hostOnly("https://relay.example.com/aigc")
        XCTAssertEqual(split.base, "https://relay.example.com")
        XCTAssertEqual(split.path, "/aigc")
    }

    func testHostOnlyNoPathIsNil() {
        let split = BYOKConfig.hostOnly("https://api.openai.com")
        XCTAssertEqual(split.base, "https://api.openai.com")
        XCTAssertNil(split.path)
    }

    func testHostOnlyKeepsQuery() {
        let split = BYOKConfig.hostOnly("https://x.example.com/aigc?api-version=2024")
        XCTAssertEqual(split.base, "https://x.example.com")
        XCTAssertEqual(split.path, "/aigc")
        XCTAssertEqual(split.query, "api-version=2024")
    }

    func testFoldIsSlashSafeForLeadinglessPath() {
        let folded = BYOKConfig.fold(
            base: "https://relay.example.com/aigc",
            path: "v1/chat/completions"
        )
        XCTAssertEqual(folded.path, "/aigc/v1/chat/completions")
    }

    func testModelsURLPreservesQuery() {
        let u = BYOKConfig.modelsURL(base: "https://x.example.com", path: "/v1/chat/completions?api-version=2024")
        XCTAssertEqual(u?.absoluteString, "https://x.example.com/v1/models?api-version=2024")
    }

    func testFoldIsIdempotent() {
        let f1 = BYOKConfig.fold(base: "https://relay.example.com/aigc", path: "/v1/chat/completions")
        let f2 = BYOKConfig.fold(base: f1.base, path: f1.path)
        XCTAssertEqual(f1.base, "https://relay.example.com")
        XCTAssertEqual(f1.path, "/aigc/v1/chat/completions")
        XCTAssertEqual(f1.base, f2.base); XCTAssertEqual(f1.path, f2.path) // re-save adds nothing
    }

    func testFoldPreservesBaseQuery() {
        let f = BYOKConfig.fold(base: "https://x.example.com/aigc?api-version=2024", path: "/v1/chat/completions")
        XCTAssertEqual(f.base, "https://x.example.com")
        XCTAssertEqual(f.path, "/aigc/v1/chat/completions?api-version=2024")
    }

    func testFoldDeduplicatesSharedAPIVersionSegment() {
        let f = BYOKConfig.fold(base: "https://api.example.com/v1", path: "/v1/chat/completions")
        XCTAssertEqual(BYOKConfig.chatURL(base: f.base, path: f.path)?.absoluteString,
                       "https://api.example.com/v1/chat/completions")
    }

    func testFoldAcceptsCompleteAnthropicRequestURLWithoutDuplicatingMessagesPath() {
        let f = BYOKConfig.fold(
            base: "https://relay.example.com/apps/anthropic/v1/messages",
            path: "/v1/messages"
        )

        XCTAssertEqual(f.base, "https://relay.example.com")
        XCTAssertEqual(f.path, "/apps/anthropic/v1/messages")
        XCTAssertEqual(
            BYOKConfig.chatURL(base: f.base, path: f.path)?.absoluteString,
            "https://relay.example.com/apps/anthropic/v1/messages"
        )
    }

    func testSnapshotAcceptsCompleteAnthropicRequestURLWithoutDuplicatingMessagesPath() {
        let snapshot = BYOKSnapshot(
            baseURL: "https://relay.example.com/apps/anthropic/v1/messages",
            apiPath: "/v1/messages",
            apiFormat: .anthropic,
            model: "relay-model",
            apiKey: "",
            reasoningEffort: "default",
            customSystem: "",
            customUser: ""
        )

        XCTAssertEqual(snapshot.chatURL?.absoluteString, "https://relay.example.com/apps/anthropic/v1/messages")
    }

    func testFoldJoinsAnthropicSDKBaseWithMessagesPath() {
        let f = BYOKConfig.fold(
            base: "https://dashscope.aliyuncs.com/apps/anthropic",
            path: "/v1/messages"
        )

        XCTAssertEqual(f.base, "https://dashscope.aliyuncs.com")
        XCTAssertEqual(f.path, "/apps/anthropic/v1/messages")
    }

    func testFoldDeduplicatesAnIdenticalCompleteAPIPath() {
        let f = BYOKConfig.fold(
            base: "https://relay.example.com/apps/anthropic/v1/messages?workspace=one",
            path: "/apps/anthropic/v1/messages"
        )

        XCTAssertEqual(f.path, "/apps/anthropic/v1/messages?workspace=one")
    }

    func testFoldHostOnlyBaseUnchanged() {
        let f = BYOKConfig.fold(base: "api.openai.com", path: "/v1/chat/completions")
        XCTAssertEqual(f.base, "https://api.openai.com")
        XCTAssertEqual(f.path, "/v1/chat/completions")
    }

    func testLocalDetection() {
        XCTAssertTrue(BYOKConfig.isLocal("http://localhost:11434"))
        XCTAssertTrue(BYOKConfig.isLocal("http://127.0.0.1:11434"))
        XCTAssertFalse(BYOKConfig.isLocal("https://relay.example.com"))
    }
}
