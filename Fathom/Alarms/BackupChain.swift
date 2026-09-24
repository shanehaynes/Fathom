import Foundation
import UserNotifications

// §3 edge-case table, last row: until AlarmKit reliability is proven across
// every row of the matrix, a parallel UNUserNotificationCenter chain
// (time-sensitive local notifications with 30 s custom sounds) runs offset
// +30 s from each AlarmKit fire, cancelled whenever the real alarm is
// acknowledged. Remove only if milestone-1 testing proves it redundant.
//
// The pending-notification budget is 64 system-wide, so the backup covers
// phase 1, the five chain fires, and three plateau checkpoints — not every
// E-repeat. Nine requests per occurrence keeps two overlapping alarms inside
// the budget.

enum BackupChain {
    static let offset: TimeInterval = 30
    static let plateauCheckpoints: [TimeInterval] = [360, 600, 840]

    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static let idPrefix = "fathom-backup-"

    /// Roles in fire order: phase 1, the five chain fires, the plateau checkpoints.
    static let roles: [String] = ["phase1"] + ChainTiming.offsets.map { $0.0.rawValue }
        + plateauCheckpoints.indices.map { "checkpoint-\($0)" }

    /// A pure function of the occurrence, so the engine can record the IDs
    /// before anything is scheduled.
    static func ids(occurrenceID: UUID) -> [String] {
        roles.map { "\(idPrefix)\(occurrenceID.uuidString)-\($0)" }
    }

    static func schedule(occurrenceID: UUID, parentID: UUID, phase1At: Date, phase2At: Date, pair: SoundPair) async {
        let center = UNUserNotificationCenter.current()
        // Same order as `roles`.
        var fires: [(Date, String)] = [
            (phase1At.addingTimeInterval(offset), pair.phase1File)
        ]
        for (step, off) in ChainTiming.offsets {
            fires.append((phase2At.addingTimeInterval(off + offset), pair.chainFile(step)))
        }
        for off in plateauCheckpoints {
            fires.append((phase2At.addingTimeInterval(off + offset), pair.chainFile(.e)))
        }

        for (id, (date, sound)) in zip(ids(occurrenceID: occurrenceID), fires) {
            let content = UNMutableNotificationContent()
            content.title = pair.name
            content.body = "Wake alarm"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("\(sound).caf"))
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["parentID": parentID.uuidString]
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func pendingIDs() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(idPrefix) }
    }

    static func cancel(ids: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
