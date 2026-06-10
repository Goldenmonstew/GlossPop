import Foundation

// Small non-streaming BYOK helpers for the Settings UI: list models + test connectivity.
enum BYOKClient {
    /// GET the endpoint's /models → model ids (best-effort; some relays/endpoints don't implement it).
    static func models(baseURL: String, apiPath: String, apiKey: String) async throws -> [String] {
        guard let url = BYOKConfig.modelsURL(base: baseURL, path: apiPath) else { throw RefineError.message(String(localized: "Invalid endpoint URL")) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw RefineError.message(errorDetail(data) ?? "HTTP \(code)") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            throw RefineError.message(String(localized: "No data[] in the response (this endpoint may not support /models)"))
        }
        return arr.compactMap { $0["id"] as? String }.sorted()
    }

    /// POST a small chat completion to verify base URL + path + key + model end-to-end.
    /// Sends the SAME reasoning_effort the real path uses, so a green test predicts a working translation
    /// (a non-reasoning model rejecting reasoning_effort must FAIL here, not pass).
    static func testChat(baseURL: String, apiPath: String, apiKey: String, model: String, reasoningEffort: String) async throws {
        guard let url = BYOKConfig.chatURL(base: baseURL, path: apiPath) else { throw RefineError.message(String(localized: "Invalid endpoint URL")) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        // No max_tokens: reasoning models (e.g. gpt-5.5) spend tokens reasoning before any output,
        // so a tiny cap makes the test fail with "max_tokens reached" even on a healthy endpoint.
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "Reply with: ok"]],
            "stream": false,
        ]
        if reasoningEffort != "default" { body["reasoning_effort"] = reasoningEffort }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw RefineError.message(errorDetail(data) ?? "HTTP \(code)") }
        // A 2xx can still carry an error frame or a non-chat body (common with 中转 relays) — verify shape.
        if let detail = errorDetail(data) { throw RefineError.message(detail) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]], !choices.isEmpty else {
            throw RefineError.message(String(localized: "Not a valid chat completion response (check the endpoint/model)"))
        }
    }

    private static func errorDetail(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = json["error"] as? [String: Any],
              let message = err["message"] as? String else { return nil }
        return message
    }
}
