import Foundation

/// Append-only trace of engine events, persisted in UserDefaults so a device
/// run can be reconstructed from a container pull without a console attached
/// (milestone 1 instrumentation; cheap enough to leave in).
enum EventLog {
    private static let key = "fathom.events"
    private static let limit = 200

    static func record(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var lines = UserDefaults.standard.stringArray(forKey: key) ?? []
        lines.append("\(stamp) \(message)")
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        UserDefaults.standard.set(lines, forKey: key)
    }
}
