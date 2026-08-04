import XCTest
@testable import GlossPop

final class ProviderCatalogTests: XCTestCase {
    func testPresetsAreWellFormed() {
        var seen = Set<String>()
        for p in ProviderCatalog.presets {
            XCTAssertTrue(seen.insert(p.id).inserted, "duplicate id \(p.id)")
            XCTAssertNotNil(BYOKConfig.url(p.baseURL), "invalid baseURL for \(p.id)")
            XCTAssertTrue(p.apiPath.hasPrefix("/"), "path must be absolute for \(p.id)")
            switch p.apiFormat {
            case .openAI:
                XCTAssertTrue(p.apiPath.hasSuffix("/chat/completions"), "unexpected OpenAI path for \(p.id)")
            case .anthropic:
                XCTAssertTrue(p.apiPath.hasSuffix("/messages"), "unexpected Anthropic path for \(p.id)")
            }
            if !p.isLocal { XCTAssertTrue(p.baseURL.hasPrefix("https://"), "cloud preset must be https: \(p.id)") }
        }
    }

    func testEveryPresetRoundTripsThroughMatch() {
        for p in ProviderCatalog.presets {
            XCTAssertEqual(ProviderCatalog.match(base: p.baseURL, path: p.apiPath)?.id, p.id)
        }
    }

    func testRelayOnVendorHostStaysCustom() {
        // Same host but a different path (a relay prefix) must NOT classify as the vendor preset,
        // or its editable endpoint fields would be hidden.
        XCTAssertNil(ProviderCatalog.match(base: "https://api.openai.com", path: "/aigc/v1/chat/completions"))
        XCTAssertNil(ProviderCatalog.match(base: "https://api.openai.com/relay-prefix", path: "/v1/chat/completions"))
        XCTAssertNil(ProviderCatalog.match(base: "https://relay.example.com", path: "/v1/chat/completions"))
    }

    func testLocalPresetsAreLoopback() {
        for p in ProviderCatalog.presets where p.isLocal {
            XCTAssertTrue(BYOKConfig.isLocal(p.baseURL), "\(p.id) must be loopback")
        }
    }

    func testEmptyPathDefaultsToStandardRoute() {
        XCTAssertEqual(ProviderCatalog.match(base: "https://api.openai.com", path: "")?.id, "openai")
    }

    func testAnthropicPresetsUseMessagesAPI() {
        let anthropic = ProviderCatalog.preset(id: "anthropic")
        XCTAssertEqual(anthropic?.apiPath, "/v1/messages")
        XCTAssertEqual(anthropic?.apiFormat, .anthropic)
        XCTAssertEqual(anthropic?.supportsModelDiscovery, true)

        let dashScope = ProviderCatalog.preset(id: "dashscope-anthropic")
        XCTAssertEqual(dashScope?.baseURL, "https://dashscope.aliyuncs.com")
        XCTAssertEqual(dashScope?.apiPath, "/apps/anthropic/v1/messages")
        XCTAssertEqual(dashScope?.defaultModel, "deepseek-v4-pro")
        XCTAssertEqual(dashScope?.apiFormat, .anthropic)
        XCTAssertEqual(dashScope?.supportsModelDiscovery, false)
        XCTAssertEqual(dashScope?.region, .cn)
    }

    func testDashScopeOffersSeparateOpenAIAndAnthropicPresets() throws {
        let openAI = try XCTUnwrap(ProviderCatalog.preset(id: "dashscope"))
        let anthropic = try XCTUnwrap(ProviderCatalog.preset(id: "dashscope-anthropic"))

        XCTAssertEqual(openAI.name, "阿里云百炼 · OpenAI")
        XCTAssertEqual(openAI.baseURL, "https://dashscope.aliyuncs.com")
        XCTAssertEqual(openAI.apiPath, "/compatible-mode/v1/chat/completions")
        XCTAssertEqual(openAI.apiFormat, .openAI)
        XCTAssertTrue(openAI.supportsModelDiscovery)

        XCTAssertEqual(anthropic.name, "阿里云百炼 · Anthropic")
        XCTAssertEqual(anthropic.baseURL, openAI.baseURL)
        XCTAssertEqual(anthropic.apiPath, "/apps/anthropic/v1/messages")
        XCTAssertEqual(anthropic.apiFormat, .anthropic)
        XCTAssertFalse(anthropic.supportsModelDiscovery)
    }

    func testDashScopeAnthropicCompleteURLMatchesItsPreset() {
        let preset = ProviderCatalog.match(
            base: "https://dashscope.aliyuncs.com/apps/anthropic/v1/messages",
            path: "/v1/messages"
        )

        XCTAssertEqual(preset?.id, "dashscope-anthropic")
    }

    func testDashScopeWorkspaceAnthropicEndpointDoesNotOfferModelDiscovery() {
        for host in [
            "dashscope.aliyuncs.com",
            "dashscope-intl.aliyuncs.com",
            "dashscope-us.aliyuncs.com",
        ] {
            XCTAssertFalse(
                ProviderCatalog.supportsModelDiscovery(
                    base: "https://\(host)",
                    path: "/apps/anthropic/v1/messages",
                    format: .anthropic
                ),
                host
            )
        }

        let suffixes = [
            "cn-beijing.maas.aliyuncs.com",
            "ap-southeast-1.maas.aliyuncs.com",
            "ap-northeast-1.maas.aliyuncs.com",
            "eu-central-1.maas.aliyuncs.com",
        ]
        for suffix in suffixes {
            let base = "https://workspace-id.\(suffix)/apps/anthropic"
            XCTAssertNil(ProviderCatalog.match(base: base, path: "/v1/messages"))
            XCTAssertFalse(
                ProviderCatalog.supportsModelDiscovery(
                    base: base,
                    path: "/v1/messages",
                    format: .anthropic
                ),
                suffix
            )
        }
        XCTAssertFalse(
            ProviderCatalog.supportsModelDiscovery(
                base: "https://workspace-id.cn-beijing.maas.aliyuncs.com",
                path: "/apps/anthropic/v1/messages/?workspace=test",
                format: .anthropic
            )
        )
    }

    func testAnthropicRelayAndOfficialAPIKeepModelDiscovery() {
        XCTAssertTrue(
            ProviderCatalog.supportsModelDiscovery(
                base: "https://relay.example.com/apps/anthropic",
                path: "/v1/messages",
                format: .anthropic
            )
        )
        XCTAssertTrue(
            ProviderCatalog.supportsModelDiscovery(
                base: "https://relay.dashscope.aliyuncs.com",
                path: "/apps/anthropic/v1/messages",
                format: .anthropic
            )
        )
        XCTAssertTrue(
            ProviderCatalog.supportsModelDiscovery(
                base: "https://api.anthropic.com",
                path: "/v1/messages",
                format: .anthropic
            )
        )
        XCTAssertTrue(
            ProviderCatalog.supportsModelDiscovery(
                base: "https://workspace-id.cn-beijing.maas.aliyuncs.com.evil.example",
                path: "/apps/anthropic/v1/messages",
                format: .anthropic
            )
        )
        XCTAssertTrue(
            ProviderCatalog.supportsModelDiscovery(
                base: "https://nested.workspace-id.cn-beijing.maas.aliyuncs.com",
                path: "/apps/anthropic/v1/messages",
                format: .anthropic
            )
        )
        XCTAssertTrue(
            ProviderCatalog.supportsModelDiscovery(
                base: "https://workspace-id.cn-beijing.maas.aliyuncs.com:8443",
                path: "/apps/anthropic/v1/messages",
                format: .anthropic
            )
        )
        XCTAssertTrue(
            ProviderCatalog.supportsModelDiscovery(
                base: "https://workspace-id.cn-beijing.maas.aliyuncs.com",
                path: "/proxy/apps/anthropic/v1/messages",
                format: .anthropic
            )
        )
    }

    func testDashScopeWorkspaceOpenAIEndpointKeepsItsExistingDiscoveryBehavior() {
        XCTAssertTrue(
            ProviderCatalog.supportsModelDiscovery(
                base: "https://workspace-id.cn-beijing.maas.aliyuncs.com",
                path: "/compatible-mode/v1/chat/completions",
                format: .openAI
            )
        )
    }
}
