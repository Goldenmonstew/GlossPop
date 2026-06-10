import Foundation

// Popup appearance (user preference). Compact hides the hint/provenance captions on RESULT cards for a
// cleaner card; message/error cards keep their guidance, and spinners + action buttons always stay.
enum PanelConfig {
    private static let kCompact = "panel.compact"
    static var compact: Bool {
        get { UserDefaults.standard.bool(forKey: kCompact) }
        set { UserDefaults.standard.set(newValue, forKey: kCompact) }
    }
}
