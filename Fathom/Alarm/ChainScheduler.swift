import Foundation
import SwiftUI
import AlarmKit

/// Turns a ChainPlan into real AlarmKit system alarms and keeps a log for milestone-1 testing.
@MainActor
final class ChainScheduler: ObservableObject {
    @Published var authorization: AlarmManager.AuthorizationState = AlarmManager.shared.authorizationState
    @Published var scheduled: [Alarm] = []
    @Published var log: [String] = []

    private let manager = AlarmManager.shared
    private static let warmWhite = Color(red: 0.949, green: 0.910, blue: 0.835) // #f2e8d5

    func ensureAuthorized() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            authorization = .authorized
        case .denied:
            authorization = .denied
            append("Alarm access denied — enable in Settings → Fathom.")
        case .notDetermined:
            do {
                authorization = try await manager.requestAuthorization()
            } catch {
                append("Authorization error: \(error)")
            }
        @unknown default:
            break
        }
        return authorization == .authorized
    }

    func schedule(_ plan: ChainPlan) async {
        guard await ensureAuthorized() else { return }
        var ids: [UUID] = []
        for step in plan.steps {
            let id = UUID()
            let metadata = WakeMetadata(chainID: plan.chainID, step: step.stepIndex, label: step.label)
            let stopButton = AlarmButton(text: "I'm up", textColor: .black, systemImageName: "sun.horizon")
            let alert = AlarmPresentation.Alert(title: "\(step.label)", stopButton: stopButton)
            let attributes = AlarmAttributes<WakeMetadata>(
                presentation: AlarmPresentation(alert: alert),
                metadata: metadata,
                tintColor: Self.warmWhite
            )
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(step.fireAt),
                attributes: attributes,
                stopIntent: ImUpIntent(chainID: plan.chainID),
                secondaryIntent: nil,
                sound: .named(step.soundFile)
            )
            do {
                _ = try await manager.schedule(id: id, configuration: configuration)
                ids.append(id)
                append("Scheduled step \(step.stepIndex) \(step.soundFile) at \(Self.time(step.fireAt))")
            } catch {
                append("FAILED step \(step.stepIndex): \(error)")
            }
        }
        ChainStore.save(chainID: plan.chainID, alarmIDs: ids)
        append("Chain \(plan.chainID.prefix(8)) — \(ids.count)/\(plan.steps.count) alarms armed")
        refresh()
    }

    func cancelEverything() {
        for chainID in ChainStore.allChainIDs() {
            ChainStore.cancelChain(id: chainID)
        }
        // Belt and braces: anything the daemon still knows about.
        for alarm in (try? manager.alarms) ?? [] {
            try? manager.cancel(id: alarm.id)
        }
        append("Cancelled all chains")
        refresh()
    }

    func refresh() {
        scheduled = ((try? manager.alarms) ?? []).sorted { a, b in
            (a.schedule.map(Self.nextDate) ?? .distantFuture) < (b.schedule.map(Self.nextDate) ?? .distantFuture)
        }
    }

    /// Subscribe once; the daemon pushes changes as alarms fire/stop.
    func observe() async {
        for await alarms in manager.alarmUpdates {
            scheduled = alarms
        }
    }

    private static func nextDate(_ schedule: Alarm.Schedule) -> Date {
        if case .fixed(let date) = schedule { return date }
        return .distantFuture
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    private func append(_ line: String) {
        log.insert("\(Self.time(Date())) — \(line)", at: 0)
    }
}
