import Foundation

// One parsed Server-Sent-Events frame from an Anthropic Messages stream.
enum AnthropicSSEFrame: Equatable {
    case delta(String)
    case done
    case error(String)
    case ignore
}

// Pure line parser for the Anthropic Messages streaming event schema. Event-name lines, keep-alives,
// thinking deltas and lifecycle frames do not contain user-visible text and are intentionally ignored.
enum AnthropicSSE {
    static func parse(line: String) -> AnthropicSSEFrame {
        guard line.hasPrefix("data:") else { return .ignore }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return .ignore }
        if payload == "[DONE]" { return .done }
        guard
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .ignore }

        switch json["type"] as? String {
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String,
                  !text.isEmpty
            else { return .ignore }
            return .delta(text)
        case "message_stop":
            return .done
        case "error":
            let error = json["error"] as? [String: Any]
            return .error((error?["message"] as? String) ?? "upstream error")
        default:
            return .ignore
        }
    }
}
