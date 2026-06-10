import Foundation
import Observation

// GlossPop — app-wide observable state. Placeholder for M1; grows in M2+.
@MainActor
@Observable
final class AppState {
    var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        return "v\(v)"
    }
}
