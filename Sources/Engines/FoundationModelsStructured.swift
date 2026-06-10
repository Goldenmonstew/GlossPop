import Foundation

// On-device structured output via Foundation Models @Generable (macOS 26+). Untestable on this 国行
// machine (deviceNotEligible); kept as a gated stub that throws so the orchestrator falls back to BYOK
// structured. Full @Generable mirror + respond(generating:) lands when an FM-eligible machine is available.
extension FoundationModelsEngine: StructuredRefineEngine {
    func structured(kind: InputKind, source: String, firstLanguage: String, secondLanguage: String) async throws -> StructuredResult {
        throw RefineError.message(String(localized: "Foundation Models structured output isn't wired up yet"))
    }
}
