import AppKit
import Carbon.HIToolbox

// Global hotkey via Carbon RegisterEventHotKey (PLAN §5.1) — NO resident CGEventTap,
// NO global NSEvent monitor. Verified permission-free in m0-spike. Fires on the main run loop.
@MainActor
final class HotKey {
    // nonisolated(unsafe): touched from the (nonisolated) deinit; only ever mutated on the main actor.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?
    private let onKeyDown: () -> Void

    // Carbon's C callback can capture no context; route through this single registered instance.
    // weak so the instance's lifetime is governed by its owner (AppDelegate) and deinit can run.
    // NOTE: M2 supports exactly ONE hotkey. Before the Settings Recorder / multi-shortcut work,
    // replace this with an app-level dispatcher keyed by EventHotKeyID.id.
    private static weak var current: HotKey?

    /// Returns nil if the OS rejected the registration (e.g. chord already taken).
    init?(keyCode: UInt32, modifiers: UInt32, onKeyDown: @escaping () -> Void) {
        self.onKeyDown = onKeyDown

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            // Carbon hot-key events are delivered on the main run loop.
            MainActor.assumeIsolated { HotKey.current?.onKeyDown() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
        guard installStatus == noErr else { return nil }

        let hkID = EventHotKeyID(signature: OSType(0x474C5350), id: 1) // 'GLSP'
        let regStatus = RegisterEventHotKey(keyCode, modifiers, hkID,
                                            GetApplicationEventTarget(), 0, &hotKeyRef)
        guard regStatus == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
            return nil
        }
        HotKey.current = self // only after install + register both succeed
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
