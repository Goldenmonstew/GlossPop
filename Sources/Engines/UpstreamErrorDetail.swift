import Foundation

/// Extracts a small, actionable upstream error without exposing credentials or arbitrary response bodies.
enum UpstreamErrorDetail {
    static let maximumBodyBytes = 8 * 1_024
    static let maximumPlainTextBytes = 512
    static let maximumDisplayCharacters = 180

    static func detail(from data: Data, apiKey: String) -> String? {
        guard !data.isEmpty, data.count <= maximumBodyBytes else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            guard let message = message(from: object) else { return nil }
            return sanitized(message, redacting: [apiKey])
        }

        guard data.count <= maximumPlainTextBytes,
              !data.contains(0),
              let text = String(data: data, encoding: .utf8),
              !looksLikeHTML(text),
              !looksBinary(text)
        else { return nil }
        return sanitized(text, redacting: [apiKey])
    }

    /// Reads only a bounded prefix from a failed streaming response. Transport failures while reading an
    /// already-known HTTP error fall back to status-only diagnostics; task cancellation still propagates.
    static func detail(from bytes: URLSession.AsyncBytes, apiKey: String) async throws -> String? {
        var data = Data()
        data.reserveCapacity(maximumBodyBytes)
        var complete = true

        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBodyBytes else {
                    complete = false
                    bytes.task.cancel()
                    break
                }
                data.append(byte)
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return nil
        }

        guard complete else { return nil }
        return detail(from: data, apiKey: apiKey)
    }

    static func sanitized(_ raw: String, redacting sensitiveValues: [String] = []) -> String? {
        var value = raw
        for sensitive in sensitiveValues where !sensitive.isEmpty {
            value = value.replacingOccurrences(of: sensitive, with: "••••")
        }

        value = value.replacingOccurrences(
            of: #"(?i)\bauthorization\b\s*[:=]\s*[\"']?(?:[A-Za-z][A-Za-z0-9._-]*\s+)?[^\s\"',;]+"#,
            with: "credential: ••••",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)\b(?:x-api-key|api[_ -]?key)\b\s*[:=]\s*[\"']?[^\s\"',;]+"#,
            with: "credential: ••••",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)\b(?:access[_ -]?token|refresh[_ -]?token|id[_ -]?token|token|client[_ -]?secret|secret|password)\b\s*[:=]\s*[\"']?[^\s\"',;]+"#,
            with: "credential: ••••",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)\bBearer[\t ]+[^\s\"',;]+"#,
            with: "Bearer ••••",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)\bsk-[A-Za-z0-9_-]{8,}"#,
            with: "••••",
            options: .regularExpression
        )
        value = value.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        value = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !value.isEmpty else { return nil }

        if value.count > maximumDisplayCharacters {
            return String(value.prefix(maximumDisplayCharacters - 1)) + "…"
        }
        return value
    }

    private static func message(from object: Any) -> String? {
        if let string = object as? String { return string }
        guard let dictionary = object as? [String: Any] else { return nil }

        if let error = dictionary["error"] as? String { return error }
        if let error = dictionary["error"] as? [String: Any] {
            for key in ["message", "error_description", "detail", "code", "type"] {
                if let value = error[key] as? String, !value.isEmpty { return value }
            }
        }
        for key in ["message", "error_description", "detail"] {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func looksLikeHTML(_ value: String) -> Bool {
        let prefix = value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256).lowercased()
        return prefix.hasPrefix("<") || prefix.contains("<!doctype")
            || prefix.contains("<html") || prefix.contains("<body")
    }

    private static func looksBinary(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }
}
