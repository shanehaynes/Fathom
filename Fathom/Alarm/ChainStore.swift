import Foundation
import AlarmKit

/// Persists chainID → [alarm UUID] so a dismissal (from the system alert's stop button,
/// which runs `ImUpIntent` in this process) can cancel every remaining sibling alarm.
enum ChainStore {
    private static let key = "fathom.chains"

    static func save(chainID: String, alarmIDs: [UUID]) {
        var all = load()
        all[chainID] = alarmIDs.map(\.uuidString)
        UserDefaults.standard.set(all, forKey: key)
    }

    static func alarmIDs(for chainID: String) -> [UUID] {
        (load()[chainID] ?? []).compactMap(UUID.init(uuidString:))
    }

    static func allChainIDs() -> [String] { Array(load().keys) }

    static func remove(chainID: String) {
        var all = load()
        all.removeValue(forKey: chainID)
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Cancels every alarm in the chain. Alarms that already fired or were already
    /// stopped throw on cancel — that's expected and ignored.
    static func cancelChain(id chainID: String) {
        for alarmID in alarmIDs(for: chainID) {
            try? AlarmManager.shared.cancel(id: alarmID)
        }
        remove(chainID: chainID)
    }

    private static func load() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }
}
