import Foundation

/// Builds the protocol-native engine for an immutable BYOK configuration snapshot.
enum BYOKEngineFactory {
    static func make(
        snapshot: BYOKSnapshot,
        session: URLSession = .shared
    ) -> any StructuredRefineEngine {
        switch snapshot.apiFormat {
        case .openAI:
            OpenAICompatibleEngine(snapshot: snapshot, session: session)
        case .anthropic:
            AnthropicCompatibleEngine(snapshot: snapshot, session: session)
        }
    }
}
