import Foundation

// Capture preferences (kept separate from BYOKConfig to avoid key clashes).
enum CaptureConfig {
    private static let kSyntheticCopy = "capture.syntheticCopy"
    /// Opt-in Tier-2 synthetic-Cmd-C fallback (OFF by default → the default path never touches the clipboard).
    static var syntheticCopyEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: kSyntheticCopy) }
        set { UserDefaults.standard.set(newValue, forKey: kSyntheticCopy) }
    }
}
