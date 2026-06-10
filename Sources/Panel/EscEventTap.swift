import AppKit

// Consumes the Escape key while the panel is visible so Esc dismisses the card WITHOUT also reaching the
// source app (its IME composition / Find bar / dialog). A passive NSEvent global monitor can't swallow the
// key, so we use a short-lived CGEventTap, torn down the moment the panel hides. Needs Accessibility
// (already required for capture); if tapCreate fails it simply no-ops and the outside-click monitor remains.
@MainActor
final class EscEventTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onEsc: () -> Void

    init(onEsc: @escaping () -> Void) { self.onEsc = onEsc }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<EscEventTap>.fromOpaque(refcon).takeUnretainedValue()
            // The system disables a tap that's slow or after intensive input — re-enable it.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 { // kVK_Escape
                // BARE Esc only — ⌘⌥Esc is Force Quit (and ⌃Esc etc. belong to the system/app), never
                // swallow those while the card happens to be visible.
                let mods: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
                guard event.flags.intersection(mods).isEmpty else { return Unmanaged.passUnretained(event) }
                MainActor.assumeIsolated { me.onEsc() }
                return nil // consume — don't pass Esc to the source app
            }
            return Unmanaged.passUnretained(event)
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = src
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil
        source = nil
    }
}
