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

    static func schedule(parentID: UUID, phase1At: Date, phase2At: Date, pair: SoundPair) async -> [String] {
        let center = UNUserNotificationCenter.current()
        var fires: [(String, Date, String)] = [
            ("phase1", phase1At.addingTimeInterval(offset), pair.phase1File)
        ]
        for (step, off) in ChainTiming.offsets {
            fires.append((step.rawValue, phase2At.addingTimeInterval(off + offset), pair.chainFile(step)))
        }
        for (i, off) in plateauCheckpoints.enumerated() {
            fires.append(("checkpoint-\(i)", phase2At.addingTimeInterval(off + offset), pair.chainFile(.e)))
        }

        var ids: [String] = []
        for (role, date, sound) in fires {
            let id = "fathom-backup-\(parentID.uuidString)-\(role)"
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
            ids.append(id)
        }
        return ids
    }

    static func cancel(ids: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
