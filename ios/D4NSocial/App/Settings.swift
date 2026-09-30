import Observation
import SwiftUI

struct BlockEntry: Codable, Identifiable, Equatable {
    let handle: String
    let date: Date
    var id: String { handle }
}

/// Filter toggles, the mute word list, the block log and per-session hidden
/// counts. Persisted in UserDefaults; `Shell` pushes every change to the open
/// WebViews through `listeners`.
@Observable
final class Settings {
    static let shared = Settings()

    enum ImportMode { case replace, merge }

    struct ImportError: LocalizedError {
        var errorDescription: String? { "That is not a D4N Social or TwitterCleanser settings file." }
    }

    private let store: UserDefaults
    private static let filtersKey = "filters"
    private static let muteWordsKey = "muteWordsList"
    private static let blockLogKey = "blockLog"

    private(set) var values: [String: Bool]
    private(set) var muteWordsList: String
    private(set) var blockLog: [BlockEntry]
    /// Counts of hidden elements reported by each platform's rules, keyed by setting.
    var stats: [Platform: [String: Int]] = [:]
    @ObservationIgnored var listeners: [(Settings) -> Void] = []

    init(store: UserDefaults = .standard) {
        self.store = store
        values = store.dictionary(forKey: Self.filtersKey) as? [String: Bool] ?? [:]
        muteWordsList = store.string(forKey: Self.muteWordsKey) ?? ""
        if let data = store.data(forKey: Self.blockLogKey),
           let log = try? JSONDecoder().decode([BlockEntry].self, from: data) {
            blockLog = log
        } else {
            blockLog = []
        }
    }

    // MARK: Toggles

    func isOn(_ key: String) -> Bool { values[key] ?? Filters.defaultValue(key) }

    func set(_ key: String, _ on: Bool) {
        guard isOn(key) != on else { return }
        values[key] = on
        store.set(values, forKey: Self.filtersKey)
        notify()
    }

    func binding(_ key: String) -> Binding<Bool> {
        Binding(get: { self.isOn(key) }, set: { self.set(key, $0) })
    }

    func setMuteWords(_ words: String) {
        guard words != muteWordsList else { return }
        muteWordsList = words
        store.set(words, forKey: Self.muteWordsKey)
        notify()
    }

    /// Everything a platform's content.js needs, in its DEFAULTS shape.
    func snapshot(for platform: Platform) -> [String: Any] {
        var out: [String: Any] = [:]
        for key in Filters.keys(for: platform) { out[key] = isOn(key) }
        if platform == .x { out[Self.muteWordsKey] = muteWordsList }
        return out
    }

    func count(for key: String, platform: Platform) -> Int? { stats[platform]?[key] }

    private func notify() { listeners.forEach { $0(self) } }

    // MARK: Block log (X only for now)

    func recordBlock(_ handle: String) {
        guard !blockLog.contains(where: { $0.handle == handle }) else { return }
        blockLog.insert(BlockEntry(handle: handle, date: Date()), at: 0)
        blockLog = Array(blockLog.prefix(200))
        persistBlockLog()
    }

    func removeBlock(_ handle: String) {
        blockLog.removeAll { $0.handle == handle }
        persistBlockLog()
    }

    private func persistBlockLog() {
        store.set(try? JSONEncoder().encode(blockLog), forKey: Self.blockLogKey)
    }

    // MARK: Import and export

    /// Same envelope as the TwitterCleanser popup export (settings under a
    /// `settings` key), so files swap in either direction. The extension
    /// ignores the Instagram keys; the app ignores its extension-only ones.
    func exportJSON() -> String {
        var inner: [String: Any] = [Self.muteWordsKey: muteWordsList]
        for spec in Filters.all { inner[spec.key] = isOn(spec.key) }
        let object: [String: Any] = [
            "d4nsocial": 1,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            "exported": ISO8601DateFormatter().string(from: Date()),
            "settings": inner,
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Applies an export from the app or the extension, or a bare
    /// { key: value } object. Only known keys with the right type are taken.
    /// Returns how many settings were applied.
    @discardableResult
    func importJSON(_ data: Data, mode: ImportMode) throws -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError()
        }
        let incoming = object["settings"] as? [String: Any] ?? object
        var next = mode == .replace ? [:] : values
        var applied = 0
        for spec in Filters.all {
            if let on = incoming[spec.key] as? Bool {
                next[spec.key] = on
                applied += 1
            }
        }
        var words = mode == .replace ? "" : muteWordsList
        if let incomingWords = incoming[Self.muteWordsKey] as? String {
            words = incomingWords
            applied += 1
        }
        guard applied > 0 else { throw ImportError() }
        values = next
        muteWordsList = words
        store.set(values, forKey: Self.filtersKey)
        store.set(words, forKey: Self.muteWordsKey)
        notify()
        return applied
    }
}
