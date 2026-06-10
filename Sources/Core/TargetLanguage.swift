import Foundation

// Two-language model (user-configurable, works for any language pair):
//   firstLanguage  = the user's native / primary reading language (translation TARGET; AI dict "meaning")
//   secondLanguage = the study / comparison language (AI dict "definition"; target when source IS the first)
// Replaces the old single `target.override`. Keeps zh-Hans/zh-Hant script.
enum TargetLanguage {
    private static let kFirst = "lang.first"
    private static let kSecond = "lang.second"
    private static let kOldOverride = "target.override"

    static var firstLanguage: String {
        get {
            let v = UserDefaults.standard.string(forKey: kFirst) ?? ""
            return v.isEmpty ? defaultFirst() : v
        }
        set { UserDefaults.standard.set(newValue, forKey: kFirst) }
    }
    static var secondLanguage: String {
        get {
            let v = UserDefaults.standard.string(forKey: kSecond) ?? ""
            return v.isEmpty ? defaultSecond(for: firstLanguage) : v
        }
        set { UserDefaults.standard.set(newValue, forKey: kSecond) }
    }

    /// One-time migration from the legacy single override. An EMPTY legacy override meant "follow the
    /// system" LIVE — keep that: write nothing, the getters fall back to defaultFirst()/defaultSecond()
    /// on every read, so later system-language changes still take effect.
    /// A concrete value is pinned only when the user had one, or when they save in Settings.
    static func migrate() {
        guard UserDefaults.standard.object(forKey: kFirst) == nil else { return }
        let old = UserDefaults.standard.string(forKey: kOldOverride) ?? ""
        guard !old.isEmpty else { return }
        firstLanguage = old
        secondLanguage = defaultSecond(for: old)
    }

    /// Best guess at the user's NATIVE language (母语), not just the macOS UI language: a Chinese speaker
    /// running macOS in English has preferredLanguages like [en-GB, zh-Hans-GB] — for them "first = en"
    /// inverts the AI dictionary (释义/意思 swapped). This app's UI is Chinese-only, so when ANY preferred
    /// language is Chinese, that's the native language; otherwise the system primary.
    static func defaultFirst(preferred: [String] = Locale.preferredLanguages) -> String {
        for id in preferred {
            let lang = Locale.Language(identifier: id)
            if lang.languageCode?.identifier == "zh" { return displayCode(lang) }
        }
        if let id = preferred.first { return displayCode(Locale.Language(identifier: id)) }
        return "en"
    }
    static func defaultSecond(for first: String, preferred: [String] = Locale.preferredLanguages) -> String {
        let firstLang = Locale.Language(identifier: first)
        for id in preferred {
            let code = displayCode(Locale.Language(identifier: id))
            if !sameLanguage(Locale.Language(identifier: code), firstLang) { return code }
        }
        return first.hasPrefix("en") ? "zh-Hans" : "en"
    }

    /// Translation target: the first language, unless the text already IS the first language → second.
    static func resolve(source: Locale.Language) -> Locale.Language {
        let first = Locale.Language(identifier: firstLanguage)
        return sameLanguage(first, source) ? Locale.Language(identifier: secondLanguage) : first
    }

    // zh-Hans → zh-Hant is a legitimate target (script differs), so only Chinese-with-same-script is "same".
    static func sameLanguage(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        guard a.languageCode == b.languageCode else { return false }
        if a.languageCode?.identifier == "zh" { return a.script == b.script }
        return true
    }

    // Only Chinese needs the script (zh-Hans vs zh-Hant); everything else is the bare code ("en", not "en-Latn").
    static func displayCode(_ language: Locale.Language) -> String {
        guard let lang = language.languageCode?.identifier else { return language.minimalIdentifier }
        if lang == "zh", let script = language.script?.identifier { return "\(lang)-\(script)" }
        return lang
    }

    // Human label for a code, for the Settings pickers. Unlisted codes (e.g. a migrated "pt") get a
    // localized language name instead of the raw code.
    static func label(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "简体中文"
        case "zh-Hant": return "繁體中文"
        case "en": return "English"
        case "ja": return "日本語"
        case "ko": return "한국어"
        case "fr": return "Français"
        case "de": return "Deutsch"
        case "es": return "Español"
        case "ru": return "Русский"
        default:
            if let name = Locale.current.localizedString(forIdentifier: code) { return "\(name)(\(code))" }
            return code
        }
    }
    static let choices = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es", "ru"]
}
