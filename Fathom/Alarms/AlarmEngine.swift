import Foundation
import AlarmKit
import ActivityKit
import AppIntents
import SwiftUI
import Observation

// §3 + §7 — each armed alarm expands to a chain of system alarms
// (phase 1 + A–E + E-repeats). Every chain member carries metadata linking it
// to the parent so any dismissal cancels siblings. Chain offsets need
// second-level precision (steps every 30 s), which Alarm.Schedule.Relative cannot
// express, so every member is a .fixed(Date) for the *next* occurrence only;
// the engine reschedules on launch, on foreground, and on dismissal.
// Restart-persistence of fixed chains is spec-to-verify (milestone 1).

/// One scheduled occurrence of an alarm: the parent model ID plus every
/// system-alarm ID in its chain. Persisted so dismissal can cancel siblings
/// across launches, and written ahead of AlarmKit: each member's ID is on
/// record before the member is scheduled.
struct ScheduledChain: Codable, Sendable {
    var id: UUID
    var parentID: UUID
    var phase1At: Date
    var phase2At: Date
    var memberIDs: [UUID]
    var backupIDs: [String]
}

extension ScheduledChain {
    // Chains persisted before occurrence IDs existed decode with a fresh one.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        parentID = try c.decode(UUID.self, forKey: .parentID)
        phase1At = try c.decode(Date.self, forKey: .phase1At)
        phase2At = try c.decode(Date.self, forKey: .phase2At)
        memberIDs = try c.decode([UUID].self, forKey: .memberIDs)
        backupIDs = try c.decode([String].self, forKey: .backupIDs)
    }
}

@MainActor
@Observable
final class AlarmEngine {
    static let shared = AlarmEngine()

    private(set) var phase: WakePhase = .idle
    private(set) var activeChain: ScheduledChain?
    private var chains: [UUID: ScheduledChain] {
        didSet { persistChains() }
    }

    private let chainsKey = "fathom.chains"
    /// Bumped by each rebuild; an older rebuild still in flight stops at its next step.
    private var rebuild = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: chainsKey),
           let decoded = try? JSONDecoder().decode([UUID: ScheduledChain].self, from: data) {
            chains = decoded
        } else {
            chains = [:]
        }
    }

    private func persistChains() {
        if let data = try? JSONEncoder().encode(chains) {
            UserDefaults.standard.set(data, forKey: chainsKey)
        }
    }

    // MARK: - Authorization

    func ensureAuthorized() async -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
            return true
        case .notDetermined:
            let state = try? await manager.requestAuthorization()
            return state == .authorized
        default:
            return false
        }
    }

    // MARK: - Scheduling

    /// Cancels and reschedules every enabled alarm's entire chain (§3). Every
    /// member is on record before AlarmKit schedules it, so a rebuild that iOS
    /// cuts short leaves no alarm "I'm up" can't cancel.
    func rescheduleAll(store: AlarmStore) async {
        guard await ensureAuthorized() else { EventLog.record("rescheduleAll: not authorized"); return }
        rebuild += 1
        let generation = rebuild
        EventLog.record("rescheduleAll: cancelling \(chains.count) chain(s), phase=\(phase)")
        for chain in chains.values {
            cancelChain(chain)
        }
        await reconcile()
        for alarm in store.alarms where alarm.isEnabled {
            guard generation == rebuild else { return }   // a newer rebuild took over
            await schedule(alarm)
        }
        refreshPhase()
    }

    /// Cancels every AlarmKit alarm and backup notification that no persisted
    /// chain records: leftovers from a build iOS cut short, or from before
    /// chains were written ahead. AlarmKit doesn't expose an alarm's metadata,
    /// so the match is by ID. Safe mid-wake, because a ringing chain's members
    /// were all recorded before they were scheduled.
    func reconcile() async {
        let manager = AlarmManager.shared
        let members = Set(chains.values.flatMap(\.memberIDs))
        let orphans = ((try? manager.alarms) ?? []).map(\.id).filter { !members.contains($0) }
        for id in orphans {
            try? manager.cancel(id: id)
        }
        let pending = await BackupChain.pendingIDs()
        let backups = Set(chains.values.flatMap(\.backupIDs))
        let strays = pending.filter { !backups.contains($0) }
        BackupChain.cancel(ids: strays)
        if !orphans.isEmpty || !strays.isEmpty {
            EventLog.record("reconcile: cancelled \(orphans.count) unrecorded alarm(s), \(strays.count) backup(s)")
        }
    }

    private func schedule(_ alarm: AlarmModel) async {
        guard let t = alarm.nextFireDate() else { return }
        // Phase 2 begins at T + G measured from T (§3 timeline).
        let p2 = t.addingTimeInterval(alarm.gap)

        var fires: [(role: String, date: Date, sound: String)] = [
            ("phase1", t, alarm.pair.phase1File)
        ]
        for (step, offset) in ChainTiming.offsets {
            fires.append((step.rawValue, p2.addingTimeInterval(offset), alarm.pair.chainFile(step)))
        }
        for (i, offset) in ChainTiming.plateauRepeatOffsets.enumerated() {
            fires.append(("e-repeat-\(i)", p2.addingTimeInterval(offset), alarm.pair.chainFile(.e)))
        }

        // Write-ahead: the record exists before AlarmKit hears of the chain, and
        // each member's ID is recorded before it is scheduled. A dismissal or a
        // newer rebuild can replace the record mid-build; the build then stops.
        if let existing = chains[alarm.id] {
            cancelChain(existing)
        }
        let occurrence = UUID()
        chains[alarm.id] = ScheduledChain(
            id: occurrence, parentID: alarm.id, phase1At: t, phase2At: p2,
            memberIDs: [], backupIDs: []
        )
        var accepted = 0
        let manager = AlarmManager.shared
        for fire in fires {
            guard chains[alarm.id]?.id == occurrence else { break }
            let id = UUID()
            chains[alarm.id]?.memberIDs.append(id)
            let metadata = FathomMetadata(
                parentID: alarm.id, role: fire.role, phase2Start: p2,
                label: fire.role == "phase1" ? "\(alarm.pair.name) · gentle" : "\(alarm.pair.name) · phase two"
            )
            let alert = AlarmPresentation.Alert(
                title: "\(alarm.pair.name)",
                secondaryButton: nil,
                secondaryButtonBehavior: nil
            )
            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
                metadata: metadata,
                tintColor: Theme.warm
            )
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(fire.date),
                attributes: attributes,
                stopIntent: DismissAlarmIntent(parentID: alarm.id.uuidString),
                secondaryIntent: nil,
                sound: .named(fire.sound + ".caf")
            )
            do {
                _ = try await manager.schedule(id: id, configuration: configuration)
            } catch {
                // AlarmKit repeat limits are spec-to-verify (milestone 1) — if the
                // system rejects the plateau tail, keep what was accepted and log.
                if chains[alarm.id]?.id == occurrence {
                    chains[alarm.id]?.memberIDs.removeAll { $0 == id }
                }
                EventLog.record("schedule: rejected \(fire.role) at \(fire.date): \(error)")
                break
            }
            // Cancelled while AlarmKit was scheduling this member: the canceller
            // couldn't reach it yet, so cancel it here.
            guard chains[alarm.id]?.id == occurrence else {
                try? manager.cancel(id: id)
                break
            }
            accepted += 1
        }

        EventLog.record("schedule: \(alarm.id.uuidString.prefix(8)) phase1=\(t) accepted \(accepted)/\(fires.count) members")
        guard chains[alarm.id]?.id == occurrence else { return }
        let backupIDs = BackupChain.ids(occurrenceID: occurrence)
        chains[alarm.id]?.backupIDs = backupIDs
        await BackupChain.schedule(
            occurrenceID: occurrence, parentID: alarm.id, phase1At: t, phase2At: p2, pair: alarm.pair
        )
        if chains[alarm.id]?.id != occurrence {
            BackupChain.cancel(ids: backupIDs)
        }
    }

    private func cancelChain(_ chain: ScheduledChain) {
        let manager = AlarmManager.shared
        for id in chain.memberIDs {
            try? manager.cancel(id: id)
        }
        BackupChain.cancel(ids: chain.backupIDs)
        chains[chain.parentID] = nil
    }

    // MARK: - Dismissal

    /// "I'm up." Cancels everything downstream — phase 2 provably never fires
    /// if dismissed during phase 1 or the gap (§3, reliability row 8).
    func dismiss(parentID: UUID, store: AlarmStore, source: String) async {
        EventLog.record("dismiss: \(parentID.uuidString.prefix(8)) via \(source), phase=\(phase), chain present=\(chains[parentID] != nil)")
        if let chain = chains[parentID] {
            for id in chain.memberIDs {
                try? AlarmManager.shared.stop(id: id)
                try? AlarmManager.shared.cancel(id: id)
            }
            BackupChain.cancel(ids: chain.backupIDs)
            chains[parentID] = nil
        }
        WakeAudio.shared.stop()
        phase = .done
        // One-shot alarms disarm; repeating alarms return to scheduled-for-tomorrow.
        if var alarm = store.alarms.first(where: { $0.id == parentID }) {
            if alarm.days.isEmpty {
                alarm.isEnabled = false
                store.update(alarm)
            } else {
                await schedule(alarm)
            }
        }
        refreshPhase()
    }

    /// Dismiss whatever is currently ringing (Wake screen's single affordance).
    func dismissActive(store: AlarmStore) async {
        if let chain = activeChain {
            await dismiss(parentID: chain.parentID, store: store, source: "wake-screen")
        } else {
            phase = .done
        }
    }

    // MARK: - Phase from wall clock

    /// The state machine position is a pure function of wall-clock time against
    /// the scheduled chain — computed fresh whenever the app looks (§3, §7).
    func refreshPhase(now: Date = Date()) {
        var best: (ScheduledChain, WakePhase)?
        for chain in chains.values {
            let p1End = chain.phase1At.addingTimeInterval(ChainTiming.phase1Duration)
            let capEnd = chain.phase2At.addingTimeInterval(ChainTiming.cap)
            let p: WakePhase?
            if now >= chain.phase1At && now < p1End {
                p = .phase1Playing(started: chain.phase1At)
            } else if now >= p1End && now < chain.phase2At {
                p = .gapWaiting(phase2At: chain.phase2At)
            } else if now >= chain.phase2At && now < capEnd {
                p = .phase2(started: chain.phase2At)
            } else {
                p = nil
            }
            if let p { best = (chain, p) }   // overlapping chains: latest wins; genuinely rare (§3)
        }
        if let (chain, p) = best {
            activeChain = chain
            phase = p
        } else {
            activeChain = nil
            let next = chains.values.map(\.phase1At).filter { $0 > now }.min()
            phase = next.map { .scheduled(next: $0) } ?? .idle
        }
    }
}

/// Runs when the user stops the system alarm. Stopping *is* "I'm up" — there is
/// no snooze anywhere in the app (principle 1), so any stop cancels the whole
/// chain and the app opens into Wake → done.
struct DismissAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "I'm up"
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = false

    @Parameter(title: "Alarm")
    var parentID: String

    init() {}
    init(parentID: String) {
        self.parentID = parentID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        EventLog.record("intent: DismissAlarmIntent.perform parent=\(parentID.prefix(8))")
        if let id = UUID(uuidString: parentID) {
            await AlarmEngine.shared.dismiss(parentID: id, store: AlarmStore.shared, source: "stop-intent")
        }
        return .result()
    }
}
