import AppKit

// Tier-2 fallback (OPT-IN, off by default): synthesize ⌘C to read a selection from apps that don't expose
// AX selected text (Safari/Electron), then FULLY restore the pasteboard so the user's clipboard is untouched.
// The default Tier-1 path stays zero-clipboard; this only runs when CaptureConfig.syntheticCopyEnabled.
@MainActor
enum SyntheticCopyCapture {
    private static var inProgress = false   // single-flight: reject reentrancy

    static func capture(timeout: TimeInterval = 0.4) -> String? {
        guard !inProgress else { return nil }
        inProgress = true
        defer { inProgress = false }

        let pb = NSPasteboard.general
        // If we can't FULLY snapshot (promised/deferred types), don't touch the clipboard at all.
        guard let saved = snapshot(pb) else { return nil }
        let before = pb.changeCount

        postCmdC()
        let deadline = Date().addingTimeInterval(timeout)
        while pb.changeCount == before, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        let copied = (pb.changeCount != before) ? pb.string(forType: .string) : nil

        restore(saved, to: pb)
        // A synthetic ⌘C can land AFTER we restored (slow app) → restore once more shortly so the user's
        // clipboard isn't left mutated.
        scheduleLateRestore(saved, afterRestoreCount: pb.changeCount)

        guard let text = copied, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func scheduleLateRestore(_ saved: [[NSPasteboard.PasteboardType: Data]], afterRestoreCount: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let pb = NSPasteboard.general
            if pb.changeCount != afterRestoreCount { restore(saved, to: pb) } // a late write happened → undo it
        }
    }

    /// Full snapshot, or nil if any item has a type whose data can't be materialized (promised/file promises) —
    /// in that case the caller must NOT proceed, since we couldn't guarantee a clean restore.
    private static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]]? {
        guard let items = pb.pasteboardItems else { return [] } // empty clipboard → safe, nothing to restore
        var result: [[NSPasteboard.PasteboardType: Data]] = []
        for item in items {
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil } // can't capture → abort Tier-2
                dict[type] = data
            }
            result.append(dict)
        }
        return result
    }

    @discardableResult
    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pb: NSPasteboard) -> Bool {
        pb.clearContents()
        guard !items.isEmpty else { return true }
        let restored = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        return pb.writeObjects(restored)
    }

    private static func postCmdC() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 0x08 // kVK_ANSI_C
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true); down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false); up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
