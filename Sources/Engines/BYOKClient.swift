import Foundation

// Small non-streaming BYOK helper for the Settings UI: list models.
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

    private static func errorDetail(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = json["error"] as? [String: Any],
              let message = err["message"] as? String else { return nil }
        return message
    }
}
