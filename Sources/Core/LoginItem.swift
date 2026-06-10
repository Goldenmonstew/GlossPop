import ServiceManagement

// Launch at login via SMAppService (macOS 13+; no helper bundle, no entitlement needed for a non-sandboxed app).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    // Registered but the user must approve it in System Settings ▸ General ▸ Login Items.
    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    // The toggle should stay ON for both states (else a pending item looks un-enabled and re-toggling loops).
    static var isActive: Bool { let s = SMAppService.mainApp.status; return s == .enabled || s == .requiresApproval }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            }
            return true
        } catch {
            return false
        }
    }
}
