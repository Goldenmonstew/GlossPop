import Foundation
import FoundationModels

// On-device LLM refine via Apple Foundation Models (macOS 26+, Apple Silicon, Apple Intelligence on).
// Unavailable on 国行 / AI-off machines (deviceNotEligible — confirmed in m0-spike), where the
// orchestrator falls back to BYOK. Non-streaming respond().
struct FoundationModelsEngine: RefineEngine {
    var label: String { String(localized: "Apple on-device model") }
    var provenance: String { String(localized: " · on-device") }

    func isAvailable() async -> Bool {
        guard #available(macOS 26, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func refine(source: String, draft: String, targetCode: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard #available(macOS 26, *) else {
                continuation.finish(throwing: RefineError.message("Foundation Models needs macOS 26."))
                return
            }
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: RefinePrompt.system)
                    let prompt = RefinePrompt.user(source: source, draft: draft, targetCode: targetCode)
                    let response = try await session.respond(to: prompt)
                    continuation.yield(response.content)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
