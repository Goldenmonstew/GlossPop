import AppKit
import ApplicationServices

// Result of an on-demand capture. Tier-1 is AX-first (zero clipboard); Tier-2 synthetic-copy is OPT-IN
// (off by default, PLAN §5.1) for apps that don't expose AX selected text.
enum CaptureResult: Equatable {
    case text(String, synthetic: Bool)  // synthetic=true → Tier-2 used ⌘C (clipboard restored), not zero side-effect
    case accessibilityDenied  // TCC not granted (kAXErrorAPIDisabled is authoritative)
    case empty                // a real element, but nothing selected
    case unreadable           // app exposes no AXSelectedText (Safari/Electron/secure fields)
}

// AX-first selected-text capture (PLAN §5.1). Never touches the clipboard; never reads our own app.
@MainActor
enum TextCapture {
    static func capture() -> CaptureResult {
        guard AXIsProcessTrusted() else { return .accessibilityDenied }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        if focusErr == .apiDisabled { return .accessibilityDenied }
        guard focusErr == .success, let ref = focused,
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return tier2Fallback() }
        let element = ref as! AXUIElement

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return .unreadable }
        if pid == selfPID { return .unreadable } // our own panel/window got focus — not a real source

        var selected: CFTypeRef?
        let selErr = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selected)
        switch selErr {
        case .success:
            // Whitespace-only selection → treat as empty (else the card shows a blank result).
            if let string = selected as? String,
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .text(string, synthetic: false) }
            return .empty                      // real element, genuinely nothing selected
        case .apiDisabled:
            return .accessibilityDenied
        default:
            return tier2Fallback()             // Safari/Electron/secure: AX has no selected text → try Tier-2
        }
    }

    /// Opt-in synthetic-⌘C fallback (clipboard fully restored). Default stays .unreadable (zero clipboard).
    private static func tier2Fallback() -> CaptureResult {
        guard CaptureConfig.syntheticCopyEnabled, let text = SyntheticCopyCapture.capture() else { return .unreadable }
        return .text(text, synthetic: true)
    }
}
