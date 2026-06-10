import AppKit
import Carbon.HIToolbox

// Persisted user hotkey (default ⌃⌘T). Stores Carbon keyCode + modifiers + a display key string.
enum HotKeyConfig {
    private static let kCode = "hotkey.keyCode"
    private static let kMods = "hotkey.modifiers"
    private static let kKey = "hotkey.displayKey"

    static var keyCode: UInt32 {
        get { (UserDefaults.standard.object(forKey: kCode) as? Int).map(UInt32.init) ?? UInt32(kVK_ANSI_T) }
        set { UserDefaults.standard.set(Int(newValue), forKey: kCode) }
    }
    static var modifiers: UInt32 {
        get { (UserDefaults.standard.object(forKey: kMods) as? Int).map(UInt32.init) ?? UInt32(controlKey | cmdKey) }
        set { UserDefaults.standard.set(Int(newValue), forKey: kMods) }
    }
    static var displayKey: String {
        get { UserDefaults.standard.string(forKey: kKey) ?? "T" }
        set { UserDefaults.standard.set(newValue, forKey: kKey) }
    }
    static var displayString: String { KeyChord.symbols(carbon: modifiers) + displayKey }
}

enum KeyChord {
    struct Candidate { let keyCode: UInt32; let modifiers: UInt32; let displayKey: String }

    /// A valid global-hotkey chord from a key event, or nil. Requires Control or Option so we don't
    /// let the user capture ordinary typing / menu shortcuts (⌘C, ⇧A, ⌘Space …) as the global hotkey.
    static func candidate(from event: NSEvent) -> Candidate? {
        let carbon = carbonModifiers(event.modifierFlags)
        guard carbon & UInt32(controlKey) != 0 || carbon & UInt32(optionKey) != 0 else { return nil }
        return Candidate(keyCode: UInt32(event.keyCode), modifiers: carbon, displayKey: displayKey(for: event))
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    static func symbols(carbon: UInt32) -> String {
        var s = ""
        if carbon & UInt32(controlKey) != 0 { s += "⌃" }
        if carbon & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbon & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbon & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    static func displayKey(for event: NSEvent) -> String {
        if let special = specialKeys[event.keyCode] { return special }
        let ch = event.charactersIgnoringModifiers ?? ""
        return ch.uppercased().isEmpty ? "Key\(event.keyCode)" : ch.uppercased()
    }

    private static let specialKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Escape): "⎋", UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
    ]
}
