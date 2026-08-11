import Foundation
import Observation

// Persistence: a single local JSON file (§7 — the model is tiny; SwiftData
// would be machinery without benefit). No network entitlements, ever.

struct Settings: Codable, Sendable {
    var bedsideMode: Bool = false
    var redShift: Bool = false
    /// v2 flag (§8). Persisted so the toggle survives, but nothing acts on it in v1.
    var sunriseLamp: Bool = false
}

struct StoreFile: Codable, Sendable {
    var alarms: [AlarmModel] = []
    var settings: Settings = Settings()
}

@MainActor
@Observable
final class AlarmStore {
    static let shared = AlarmStore()

    var alarms: [AlarmModel] {
        didSet { save() }
    }
    var settings: Settings {
        didSet { save() }
    }

    private let url: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("fathom.json")
        if let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(StoreFile.self, from: data) {
            alarms = file.alarms
            settings = file.settings
        } else {
            // First launch: one weekday 6:10 alarm, disabled until the user arms it.
            alarms = [AlarmModel(hour: 6, minute: 10,
                                 days: [.monday, .tuesday, .wednesday, .thursday, .friday],
                                 isEnabled: false)]
            settings = Settings()
        }
    }

    private func save() {
        let file = StoreFile(alarms: alarms, settings: settings)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The soonest upcoming (alarm, fire date) across enabled alarms.
    var nextWake: (alarm: AlarmModel, date: Date)? {
        alarms.compactMap { a in a.nextFireDate().map { (a, $0) } }
            .min { $0.1 < $1.1 }
    }

    func update(_ alarm: AlarmModel) {
        if let i = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[i] = alarm
        } else {
            alarms.append(alarm)
        }
    }
}
