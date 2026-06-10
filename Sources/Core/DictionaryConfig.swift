import Foundation

// How a word/phrase lookup is resolved (one picker, no "two toggles" that could
// silently send to the cloud while AI is "off"). Default is fully offline.
enum DictionaryMode: String, CaseIterable, Sendable {
    case offline            // macOS system dictionary only; a miss shows a "用 AI 解释一次" button (no auto cloud)
    case offlineThenAI      // system first; on a miss, automatically use the AI dictionary
    case offlinePlusAI      // system shows instantly; AI bilingual entry is appended (progressive)
    case aiOnly             // skip the system dictionary, go straight to the AI bilingual dictionary

    var label: String {
        switch self {
        case .offline: return String(localized: "Offline (macOS system dictionary only)")
        case .offlineThenAI: return String(localized: "Offline first, AI for missing words")
        case .offlinePlusAI: return String(localized: "Offline + AI detail (system instant, AI appended)")
        case .aiOnly: return String(localized: "AI dictionary only")
        }
    }
    var usesSystem: Bool { self != .aiOnly }
    var autoAI: Bool { self == .offlineThenAI || self == .offlinePlusAI || self == .aiOnly }
    var alwaysAI: Bool { self == .offlinePlusAI || self == .aiOnly } // run AI even when the system has a hit
}

enum DictionaryConfig {
    private static let kMode = "dictionary.mode"
    static var mode: DictionaryMode {
        get { DictionaryMode(rawValue: UserDefaults.standard.string(forKey: kMode) ?? "") ?? .offline }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kMode) }
    }

    /// One-time mapping from the legacy dictionary toggle. Old behavior (v0.1.13): system hit → offline
    /// entry, miss → AUTOMATIC model translation. So:
    /// - old toggle explicitly OFF → the user wanted the model to handle words → .aiOnly
    /// - a model is configured (upgrader who already consented at save time) → .offlineThenAI keeps old behavior
    /// - fresh install / never configured → the new privacy default .offline (never auto-sends)
    static func migrate() {
        guard UserDefaults.standard.object(forKey: kMode) == nil else { return }
        let legacyOff: Bool? = UserDefaults.standard.object(forKey: "output.dictionary") == nil
            ? nil : (UserDefaults.standard.bool(forKey: "output.dictionary") == false)
        if let mapped = migratedMode(legacyDictionaryOff: legacyOff, byokReady: BYOKConfig.isReady) {
            mode = mapped
        }
    }

    /// Pure mapping (unit-tested without touching real defaults). nil = keep the .offline default.
    static func migratedMode(legacyDictionaryOff: Bool?, byokReady: Bool) -> DictionaryMode? {
        if legacyDictionaryOff == true { return .aiOnly }
        if byokReady { return .offlineThenAI }
        return nil
    }
}
