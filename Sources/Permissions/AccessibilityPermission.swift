import AppKit
import ApplicationServices

// Accessibility is the ONE required permission (TCC, no entitlement). PLAN §5.4.
@MainActor
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Triggers the system prompt (only shows once per binary identity until granted/denied).
    static func promptIfNeeded() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Opens System Settings ▸ Privacy & Security ▸ Accessibility. This anchor form works across
    /// macOS 15–26; if Apple changes it, onboarding keeps a manual-nav + Recheck path (reverse-engineered).
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
