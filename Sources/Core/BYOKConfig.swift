import Foundation

// BYOK config: one OpenAI-compatible custom endpoint (cloud / 中转 relay / local Ollama/LM Studio).
// base URL + model in UserDefaults; API key in Keychain (PLAN §4, §3). For 国行 no-FM users this is
// the primary refine path.
enum BYOKConfig {
    private static let kEnabled = "byok.enabled"
    private static let kBaseURL = "byok.baseURL"
    private static let kModel = "byok.model"
    private static let keyAccount = "byok.apiKey"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: kEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: kEnabled) }
    }
    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: kBaseURL) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kBaseURL) }
    }
    static var model: String {
        get { UserDefaults.standard.string(forKey: kModel) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: kModel) }
    }
    static var apiKey: String { Keychain.get(account: keyAccount) ?? "" }

    /// Returns false if the Keychain write failed (Settings should not claim success).
    @discardableResult
    static func setAPIKey(_ value: String) -> Bool {
        if value.isEmpty { return Keychain.delete(account: keyAccount) }
        return Keychain.set(value, account: keyAccount)
    }

    static var isReady: Bool { isEnabled && url(baseURL) != nil && !model.isEmpty }

    // Per-mode (like Bob/openai-translator): word/phrase → dictionary, sentence → +syntax. Default on.
    private static func boolDefaultTrue(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
    }
    static var sentenceAnalysisEnabled: Bool {
        get { boolDefaultTrue("output.sentence") }
        set { UserDefaults.standard.set(newValue, forKey: "output.sentence") }
    }

    // Reasoning effort ("default" = OMIT the param). Default "default" so NON-reasoning models (e.g.
    // gpt-4o-mini) aren't rejected with HTTP 400 — reasoning-model users opt into "low" for speed.
    static var reasoningEffort: String {
        get { UserDefaults.standard.string(forKey: "model.reasoningEffort") ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: "model.reasoningEffort") }
    }

    // API path appended to the host base (like the competitor's "Custom API Path"), default OpenAI's.
    private static let kApiPath = "byok.apiPath"
    static var apiPath: String {
        get { UserDefaults.standard.string(forKey: kApiPath) ?? "/v1/chat/completions" }
        set { UserDefaults.standard.set(newValue, forKey: kApiPath) }
    }

    // Custom prompt (advanced): overrides the built-in plain-translation prompt. $text / $target substituted.
    static var customPromptEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "prompt.customEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "prompt.customEnabled") }
    }
    static var customSystemPrompt: String {
        get { UserDefaults.standard.string(forKey: "prompt.system") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "prompt.system") }
    }
    static var customUserPrompt: String {
        get { UserDefaults.standard.string(forKey: "prompt.user") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "prompt.user") }
    }

    /// One-time launch migration: split a legacy full base URL into host-base + apiPath, PRESERVING the exact
    /// old request URL (old code did `base.appending(path: "chat/completions")`), then derive base via
    /// URLComponents so host/port/IPv6/userinfo survive. Also heal a stale enabled=false.
    static func migrateURLSplitIfNeeded() {
        if UserDefaults.standard.object(forKey: kApiPath) == nil, let oldBase = url(baseURL) {
            let oldChat = oldBase.appending(path: "chat/completions")          // EXACT pre-migration URL
            if var comp = URLComponents(url: oldChat, resolvingAgainstBaseURL: false), comp.host != nil {
                let pathQuery = comp.path + (comp.query.map { "?\($0)" } ?? "")
                comp.path = ""; comp.query = nil; comp.fragment = nil          // base = scheme://[user@]host[:port]
                if let hostBase = comp.string {
                    baseURL = hostBase
                    apiPath = pathQuery.isEmpty ? "/v1/chat/completions" : pathQuery
                }
            }
        }
        // Configured-but-disabled (legacy enabled toggle removed) → heal so translation works — but NEVER
        // auto-enable an un-consented CLOUD endpoint (that would send text to a third party on first hotkey
        // without the consent prompt). Local is always safe; remote only if already consented.
        if !isEnabled, !model.isEmpty, let u = url(baseURL) {
            if isLocal(baseURL) || consentedHost == (u.host ?? "") { isEnabled = true }
        }
    }

    /// Reduce a user/path string to PATH (+query) only, dropping any scheme/host so `apiPath` can never
    /// redirect the request to another host or bypass consent. Defaults to the OpenAI route.
    static func sanitizedPath(_ raw: String) -> (path: String, query: String?) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comp = URLComponents(string: t), comp.host != nil {   // someone pasted a full URL → keep only path+query
            return (comp.path.isEmpty ? "/v1/chat/completions" : comp.path, comp.query)
        }
        var p = t.isEmpty ? "/v1/chat/completions" : t
        if !p.hasPrefix("/") { p = "/" + p }
        if let q = p.firstIndex(of: "?") { return (String(p[..<q]), String(p[p.index(after: q)...])) }
        return (p, nil)
    }

    /// Split a base URL into a host-only base + any path it carried (so a user who pastes ".../aigc" into the
    /// base field doesn't silently lose that prefix — it's folded into the path).
    static func hostOnly(_ base: String) -> (base: String, path: String?, query: String?) {
        guard let u = url(base), var comp = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return (base, nil, nil) }
        let path = comp.path, query = comp.query
        comp.path = ""; comp.query = nil; comp.fragment = nil
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return (comp.string ?? base, (trimmed.isEmpty || trimmed == "/") ? nil : trimmed, query)
    }

    /// Single source of truth for normalizing user input into (host-only base, full path[+query]). Used by
    /// save() AND testConnection()/fetchModels() so the tested endpoint is ALWAYS the persisted one.
    static func fold(base rawBase: String, path rawPath: String) -> (base: String, path: String) {
        let split = hostOnly(normalized(rawBase))
        let ap = sanitizedPath(rawPath)
        let mergedQuery = ap.query ?? split.query
        return (split.base, (split.path ?? "") + ap.path + (mergedQuery.map { "?\($0)" } ?? ""))
    }

    /// Full chat-completions URL = host base + path, built via URLComponents (no string injection). The path
    /// is host-stripped, so `apiPath` stays a path on the configured host. nil if base isn't a valid host.
    static func chatURL(base: String, path: String) -> URL? {
        guard let host = url(base), var comp = URLComponents(url: host, resolvingAgainstBaseURL: false) else { return nil }
        let cleaned = sanitizedPath(path)
        comp.path = cleaned.path
        comp.query = cleaned.query
        return comp.url
    }
    /// Derive the /models URL from the chat path (…/chat/completions SUFFIX → …/models; else /v1/models),
    /// preserving any query so it matches the chat endpoint (e.g. ?api-version=…).
    static func modelsURL(base: String, path: String) -> URL? {
        let parts = sanitizedPath(path)
        let suffix = "/chat/completions"
        let modelsPath = parts.path.hasSuffix(suffix) ? String(parts.path.dropLast(suffix.count)) + "/models" : "/v1/models"
        return chatURL(base: base, path: modelsPath + (parts.query.map { "?\($0)" } ?? ""))
    }

    private static let kConsentedHost = "byok.consentedHost"
    /// The cloud/relay host the user already consented to send text to (so we ask only once, not every save).
    static var consentedHost: String? {
        get { UserDefaults.standard.string(forKey: kConsentedHost) }
        set { UserDefaults.standard.set(newValue, forKey: kConsentedHost) }
    }

    /// Normalize a user-typed base URL: trim + prefix https:// if no scheme (so "host/v1" works).
    static func normalized(_ string: String) -> String {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        // Only prefix https:// when there's NO scheme at all (else "ftp://x" → "https://ftp://x").
        return t.contains("://") ? t : "https://" + t
    }

    /// A VALID http(s) URL with a real host, or nil. Prevents `URL(string:"localhost:11434/v1")`
    /// parsing "localhost" as a scheme (host==nil) — which inverted the privacy badge.
    static func url(_ string: String) -> URL? {
        guard let u = URL(string: normalized(string)),
              let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = u.host, !host.isEmpty else { return nil }
        return u
    }

    /// Loopback ONLY counts as on-device (LAN/relay = text leaves this Mac — PLAN §3).
    static func isLocal(_ urlString: String) -> Bool {
        guard let host = url(urlString)?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    static func host(_ urlString: String) -> String { url(urlString)?.host ?? urlString }

    /// Immutable snapshot captured when a refine starts, so request + provenance stay consistent
    /// even if the user edits settings mid-stream (privacy promise).
    static func snapshot() -> BYOKSnapshot? {
        guard isReady else { return nil }
        return BYOKSnapshot(baseURL: normalized(baseURL), apiPath: apiPath, model: model, apiKey: apiKey,
                            reasoningEffort: reasoningEffort,
                            customSystem: customPromptEnabled ? customSystemPrompt : "",
                            customUser: customPromptEnabled ? customUserPrompt : "")
    }
}

struct BYOKSnapshot: Sendable {
    let baseURL: String
    let apiPath: String
    let model: String
    let apiKey: String
    let reasoningEffort: String      // "default" = omit the param
    let customSystem: String         // empty = use the built-in prompt
    let customUser: String
    var host: String { BYOKConfig.host(baseURL) }
    var isLocal: Bool { BYOKConfig.isLocal(baseURL) }
    var chatURL: URL? { BYOKConfig.chatURL(base: baseURL, path: apiPath) }
    // Result card shows the MODEL (like Bob/openai-translator), not the raw endpoint — but still marks the
    // DESTINATION (本机 vs 云) so the panel honors the "标注去向" promise without exposing the URL.
    var label: String { model }
    var provenance: String { isLocal ? String(localized: " · on-device") : String(localized: " · cloud") }
}
