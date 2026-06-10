import Foundation

struct HistoryEntry: Codable, Sendable, Identifiable {
    var id = UUID()
    let source: String
    let result: String
    let subtitle: String
    let date: Date
}

// Local-only translation history (UserDefaults JSON, capped). Off-switchable for privacy.
@MainActor
enum HistoryStore {
    private static let kEntries = "history.entries"
    private static let kEnabled = "history.enabled"
    private static let maxEntries = 50

    // Opt-in (default OFF): history stores source/result in plaintext locally, so don't keep it without consent.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: kEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: kEnabled); if !newValue { clear() } }
    }

    private static let maxStored = 2000  // don't persist whole-page selections verbatim in the plist

    static func record(source: String, result: String, subtitle: String) {
        let src = String(source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxStored))
        let res = String(result.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxStored))
        guard isEnabled, !src.isEmpty, !res.isEmpty else { return }
        var list = all()
        list.removeAll { $0.source == src }   // drop a prior identical source so re-translates float to top
        list.insert(HistoryEntry(source: src, result: res, subtitle: subtitle, date: Date()), at: 0)
        if list.count > maxEntries { list = Array(list.prefix(maxEntries)) }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: kEntries) }
    }

    static func all() -> [HistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: kEntries),
              let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [] }
        return list
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: kEntries) }
}
