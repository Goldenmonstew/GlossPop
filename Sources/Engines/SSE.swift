import Foundation

// One parsed Server-Sent-Events frame from an OpenAI-compatible stream.
enum SSEFrame: Equatable {
    case delta(String)   // incremental text to append
    case done            // [DONE] sentinel
    case error(String)   // an error frame inside a 200 stream (common with 中转 relays)
    case ignore          // keep-alive / comment / unparseable / empty delta
}

// Pure, testable SSE line parser. Handles streaming `delta.content` AND non-stream `message.content`.
enum SSE {
    static func parse(line: String) -> SSEFrame {
        guard line.hasPrefix("data:") else { return .ignore } // ignore comments/event:/empty lines
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty { return .ignore }
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .ignore }
        if let err = json["error"] as? [String: Any] {
            return .error((err["message"] as? String) ?? "upstream error")
        }
        guard let first = (json["choices"] as? [[String: Any]])?.first else { return .ignore }
        if let delta = (first["delta"] as? [String: Any])?["content"] as? String, !delta.isEmpty { return .delta(delta) }
        if let message = (first["message"] as? [String: Any])?["content"] as? String, !message.isEmpty { return .delta(message) }
        return .ignore
    }
}
