import XCTest
@testable import GlossPop

final class BYOKConfigTests: XCTestCase {
    // The privacy P0: a scheme-less loopback URL must NOT be classified as cloud.
    func testSchemeLessLocalhostIsLocal() {
        XCTAssertTrue(BYOKConfig.isLocal("localhost:11434/v1"))
        XCTAssertTrue(BYOKConfig.isLocal("http://127.0.0.1:11434/v1"))
        XCTAssertTrue(BYOKConfig.isLocal("https://localhost/v1"))
    }

    func testCloudIsNotLocal() {
        XCTAssertFalse(BYOKConfig.isLocal("api.openai.com/v1"))
        XCTAssertFalse(BYOKConfig.isLocal("https://relay.example.com/aigc/v1"))
    }

    func testURLValidation() {
        XCTAssertNotNil(BYOKConfig.url("api.openai.com/v1"))      // scheme auto-prefixed
        XCTAssertNotNil(BYOKConfig.url("https://api.openai.com/v1"))
        XCTAssertNil(BYOKConfig.url(""))                          // empty
        XCTAssertNil(BYOKConfig.url("not a url"))                 // space → invalid
        XCTAssertNil(BYOKConfig.url("ftp://example.com"))         // wrong scheme
    }

    func testNormalizePrefixesHTTPS() {
        XCTAssertEqual(BYOKConfig.normalized("api.openai.com/v1"), "https://api.openai.com/v1")
        XCTAssertEqual(BYOKConfig.normalized("http://x/v1"), "http://x/v1")   // keeps explicit scheme
        XCTAssertEqual(BYOKConfig.normalized("  https://x/v1  "), "https://x/v1") // trims
    }

    func testHostExtraction() {
        XCTAssertEqual(BYOKConfig.host("relay.example.com/aigc/v1"), "relay.example.com")
    }

    func testMissingOrInvalidAPIFormatDefaultsToOpenAI() {
        let defaults = UserDefaults.standard
        let key = "byok.apiFormat"
        let originalValue = defaults.object(forKey: key)
        defer { restore(originalValue, forKey: key, in: defaults) }

        defaults.removeObject(forKey: key)
        XCTAssertEqual(BYOKConfig.apiFormat, .openAI)

        defaults.set("unsupported", forKey: key)
        XCTAssertEqual(BYOKConfig.apiFormat, .openAI)
    }

    func testMissingOrInvalidAPIKeyHeaderDefaultsToAutomatic() {
        let defaults = UserDefaults.standard
        let key = "byok.apiKeyHeader"
        let originalValue = defaults.object(forKey: key)
        defer { restore(originalValue, forKey: key, in: defaults) }

        defaults.removeObject(forKey: key)
        XCTAssertEqual(BYOKConfig.apiKeyHeader, .automatic)

        defaults.set("unsupported", forKey: key)
        XCTAssertEqual(BYOKConfig.apiKeyHeader, .automatic)
    }

    func testMissingAPIPathUsesTheSelectedFormatsDefault() {
        let defaults = UserDefaults.standard
        let keys = ["byok.apiFormat", "byok.apiPath"]
        let originalValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys { restore(originalValues[key] ?? nil, forKey: key, in: defaults) }
        }

        defaults.removeObject(forKey: "byok.apiPath")
        BYOKConfig.apiFormat = .openAI
        XCTAssertEqual(BYOKConfig.apiPath, "/v1/chat/completions")

        BYOKConfig.apiFormat = .anthropic
        XCTAssertEqual(BYOKConfig.apiPath, "/v1/messages")

        defaults.set("  ", forKey: "byok.apiPath")
        XCTAssertEqual(BYOKConfig.apiPath, "/v1/messages")
    }

    func testMigrationUsesTheExplicitAnthropicFormatWhenPathIsMissing() {
        let defaults = UserDefaults.standard
        let keys = ["byok.enabled", "byok.baseURL", "byok.model", "byok.apiFormat", "byok.apiPath"]
        let originalValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys { restore(originalValues[key] ?? nil, forKey: key, in: defaults) }
        }

        BYOKConfig.isEnabled = true
        BYOKConfig.baseURL = "https://relay.example.com/apps/anthropic"
        BYOKConfig.model = "relay-model"
        BYOKConfig.apiFormat = .anthropic
        defaults.removeObject(forKey: "byok.apiPath")

        BYOKConfig.migrateURLSplitIfNeeded()

        XCTAssertEqual(BYOKConfig.baseURL, "https://relay.example.com")
        XCTAssertEqual(BYOKConfig.apiPath, "/apps/anthropic/v1/messages")
        XCTAssertEqual(BYOKConfig.apiFormat, .anthropic)
    }

    func testAPIFormatPersistsIntoSnapshot() {
        let defaults = UserDefaults.standard
        let keys = [
            "byok.enabled",
            "byok.baseURL",
            "byok.model",
            "byok.apiFormat",
            "byok.apiKeyHeader",
            "byok.apiPath",
        ]
        let originalValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys { restore(originalValues[key] ?? nil, forKey: key, in: defaults) }
        }

        BYOKConfig.isEnabled = true
        BYOKConfig.baseURL = "https://dashscope.aliyuncs.com"
        BYOKConfig.model = "deepseek-v4-pro"
        BYOKConfig.apiFormat = .anthropic
        BYOKConfig.apiKeyHeader = .authorizationBearer
        BYOKConfig.apiPath = "/apps/anthropic/v1/messages"

        let snapshot = BYOKConfig.snapshot()
        XCTAssertEqual(snapshot?.apiFormat, .anthropic)
        XCTAssertEqual(snapshot?.apiKeyHeader, .authorizationBearer)
        XCTAssertEqual(snapshot?.forCapabilityAssessment.apiFormat, .anthropic)
        XCTAssertEqual(snapshot?.forCapabilityAssessment.apiKeyHeader, .authorizationBearer)
        XCTAssertEqual(defaults.string(forKey: "byok.apiFormat"), BYOKAPIFormat.anthropic.rawValue)
        XCTAssertEqual(
            defaults.string(forKey: "byok.apiKeyHeader"),
            BYOKAPIKeyHeader.authorizationBearer.rawValue
        )
    }

    func testLegacyOfficialAnthropicPresetMigratesToMessagesAPI() {
        let defaults = UserDefaults.standard
        let keys = [
            "byok.enabled",
            "byok.baseURL",
            "byok.model",
            "byok.apiFormat",
            "byok.apiPath",
        ]
        let originalValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys { restore(originalValues[key] ?? nil, forKey: key, in: defaults) }
        }

        BYOKConfig.isEnabled = true
        BYOKConfig.baseURL = "https://api.anthropic.com"
        BYOKConfig.model = "claude-haiku-4-5"
        BYOKConfig.apiPath = "/v1/chat/completions?beta=test"
        defaults.removeObject(forKey: "byok.apiFormat")

        BYOKConfig.migrateURLSplitIfNeeded()

        XCTAssertEqual(BYOKConfig.baseURL, "https://api.anthropic.com")
        XCTAssertEqual(BYOKConfig.apiPath, "/v1/messages?beta=test")
        XCTAssertEqual(BYOKConfig.apiFormat, .anthropic)
    }

    func testLegacyAnthropicMigrationDoesNotOverrideAnExplicitFormat() {
        let defaults = UserDefaults.standard
        let keys = ["byok.enabled", "byok.baseURL", "byok.model", "byok.apiFormat", "byok.apiPath"]
        let originalValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys { restore(originalValues[key] ?? nil, forKey: key, in: defaults) }
        }

        BYOKConfig.isEnabled = true
        BYOKConfig.baseURL = "https://api.anthropic.com"
        BYOKConfig.model = "relay-model"
        BYOKConfig.apiPath = "/custom/chat/completions"
        BYOKConfig.apiFormat = .openAI

        BYOKConfig.migrateURLSplitIfNeeded()

        XCTAssertEqual(BYOKConfig.apiPath, "/custom/chat/completions")
        XCTAssertEqual(BYOKConfig.apiFormat, .openAI)
    }

    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
