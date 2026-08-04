import Foundation

// One shared API-key policy for streaming, structured and model-discovery requests. Automatic follows the
// selected wire protocol, except loopback endpoints receive no cloud key unless the user explicitly opts in.
enum BYOKAuthentication {
    static func apply(
        apiKey: String,
        format: BYOKAPIFormat,
        header: BYOKAPIKeyHeader,
        isLocal: Bool,
        to request: inout URLRequest
    ) {
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue(nil, forHTTPHeaderField: "x-api-key")
        guard !apiKey.isEmpty else { return }

        let resolved: BYOKAPIKeyHeader
        if header == .automatic {
            if isLocal {
                resolved = .none
            } else {
                resolved = format == .anthropic ? .xAPIKey : .authorizationBearer
            }
        } else {
            resolved = header
        }

        switch resolved {
        case .authorizationBearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .xAPIKey:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        case .automatic, .none:
            break
        }
    }
}
