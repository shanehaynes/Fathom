import Foundation
import AlarmKit
import ActivityKit
import AppIntents
import SwiftUI
import Observation

// §3 + §7 — each armed alarm expands to a chain of system alarms
// (phase 1 + A–E + E-repeats). Every chain member carries metadata linking it
// to the parent so any dismissal cancels siblings. Chain offsets need
// second-level precision (B at +45 s), which Alarm.Schedule.Relative cannot
// express, so every member is a .fixed(Date) for the *next* occurrence only;
// the engine reschedules on launch, on foreground, and on dismissal.
// Restart-persistence of fixed chains is spec-to-verify (milestone 1).

/// One scheduled occurrence of an alarm: the parent model ID plus every
/// system-alarm ID in its chain. Persisted so dismissal can cancel siblings
/// across launches.
struct ScheduledChain: Codable, Sendable {
    var parentID: UUID
    var phase1At: Date
    var phase2At: Date
    var memberIDs: [UUID]
    var backupIDs: [String]
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

    /// Cancels and reschedules every enabled alarm's entire chain atomically (§3).
    func rescheduleAll(store: AlarmStore) async {
        guard await ensureAuthorized() else { return }
        for chain in chains.values {
            cancelChain(chain)
        }
        chains = [:]
        for alarm in store.alarms where alarm.isEnabled {
            await schedule(alarm)
        }
        refreshPhase()
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

        var memberIDs: [UUID] = []
        let manager = AlarmManager.shared
        for fire in fires {
            let id = UUID()
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
                memberIDs.append(id)
            } catch {
                // AlarmKit repeat limits are spec-to-verify (milestone 1) — if the
                // system rejects the plateau tail, keep what was accepted and log.
                print("Fathom: schedule rejected for \(fire.role) at \(fire.date): \(error)")
                break
            }
        }

        let backupIDs = await BackupChain.schedule(
            parentID: alarm.id, phase1At: t, phase2At: p2, pair: alarm.pair
        )

        chains[alarm.id] = ScheduledChain(
            parentID: alarm.id, phase1At: t, phase2At: p2,
            memberIDs: memberIDs, backupIDs: backupIDs
        )
    }

    private func cancelChain(_ chain: ScheduledChain) {
        let manager = AlarmManager.shared
        for id in chain.memberIDs {
            try? manager.cancel(id: id)
        }
        BackupChain.cancel(ids: chain.backupIDs)
    }

    // MARK: - Dismissal

    /// "I'm up." Cancels everything downstream — phase 2 provably never fires
    /// if dismissed during phase 1 or the gap (§3, reliability row 8).
    func dismiss(parentID: UUID, store: AlarmStore) async {
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
            await dismiss(parentID: chain.parentID, store: store)
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
        if let id = UUID(uuidString: parentID) {
            await AlarmEngine.shared.dismiss(parentID: id, store: AlarmStore.shared)
        }
        return .result()
    }
}
