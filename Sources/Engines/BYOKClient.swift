import Foundation

// Small non-streaming BYOK helper for the Settings UI: list models.
enum BYOKClient {
    /// GET the endpoint's /models → model ids (best-effort; some relays/endpoints don't implement it).
    static func models(
        baseURL: String,
        apiPath: String,
        apiFormat: BYOKAPIFormat,
        apiKeyHeader: BYOKAPIKeyHeader,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [String] {
        guard let url = BYOKConfig.modelsURL(base: baseURL, path: apiPath) else { throw RefineError.message(String(localized: "Invalid endpoint URL")) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if apiFormat == .anthropic {
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        BYOKAuthentication.apply(
            apiKey: apiKey,
            format: apiFormat,
            header: apiKeyHeader,
            isLocal: BYOKConfig.isLocal(baseURL),
            to: &req
        )
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw RefineError.http(
                statusCode: code,
                host: url.host ?? BYOKConfig.host(baseURL),
                detail: UpstreamErrorDetail.detail(from: data, apiKey: apiKey)
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            throw RefineError.message(String(localized: "No data[] in the response (this endpoint may not support /models)"))
        }
        return arr.compactMap { $0["id"] as? String }.sorted()
    }

}
