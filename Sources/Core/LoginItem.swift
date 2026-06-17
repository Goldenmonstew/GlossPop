import Foundation
import ServiceManagement

// Launch at login via SMAppService (macOS 13+; no helper bundle, no entitlement needed for a non-sandboxed app).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    // Registered but the user must approve it in System Settings ▸ General ▸ Login Items.
    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    // The toggle should stay ON for both states (else a pending item looks un-enabled and re-toggling loops).
    static var isActive: Bool { let s = SMAppService.mainApp.status; return s == .enabled || s == .requiresApproval }

    // SMAppService.status alone cannot tell "the OS dropped the item" (major upgrades reset
    // background-item approval) apart from "the user never enabled it" — persist the intent.
    private static let intentKey = "loginItem.userWantsEnabled"
    static var userWantsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: intentKey) }
        set { UserDefaults.standard.set(newValue, forKey: intentKey) }
    }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            }
            userWantsEnabled = on
            return true
        } catch {
            return false
        }
    }

    enum ReconcileAction: Equatable {
        case none       // in sync, or the user never opted in
        case register   // the OS lost the registration → re-register silently
    }

    // Pure decision so the upgrade matrix is unit-testable without touching the live service.
    // .requiresApproval is deliberately NOT re-registered: register() cannot clear it, only the
    // user can (System Settings), so it is surfaced live in the menu instead.
    static func reconcileAction(userWants: Bool, status: SMAppService.Status) -> ReconcileAction {
        guard userWants else { return .none }
        switch status {
        case .enabled, .requiresApproval: return .none
        default: return .register   // .notRegistered / .notFound / future cases
        }
    }

    // Raised only when pending approval is found AT LAUNCH (where an OS-upgrade reset lands) or
    // right after a launch-time self-heal. A mid-run revoke in System Settings is user intent —
    // it never raises the flag, so the menu does not fight a deliberate disable.
    @MainActor private(set) static var nudgeForApproval = false

    /// Launch-time reconciliation: migrate the intent flag for installs that predate it (only the
    /// app ever registers, so a registered item — even one pending approval — proves past intent),
    /// and re-register a login item the OS dropped (e.g. a major-upgrade background-items reset).
    @MainActor static func reconcileAtLaunch() {
        switch SMAppService.mainApp.status {
        case .enabled:
            userWantsEnabled = true
        case .requiresApproval:
            userWantsEnabled = true
            nudgeForApproval = true
        default:
            if reconcileAction(userWants: userWantsEnabled, status: SMAppService.mainApp.status) == .register {
                try? SMAppService.mainApp.register()
                if requiresApproval { nudgeForApproval = true }   // healed into pending → still needs the user
            }
        }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
