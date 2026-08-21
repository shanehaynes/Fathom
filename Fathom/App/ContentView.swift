import SwiftUI
import AlarmKit

/// Milestone-1 walking skeleton. Not the real UI — a test bench for proving that
/// chained AlarmKit alarms fire on a real phone under every row of DESIGN.md §9.
struct ContentView: View {
    @EnvironmentObject private var scheduler: ChainScheduler

    @State private var firstSoundInMinutes: Double = 2
    @State private var gapMinutes: Double = 1
    @State private var plateauRepeats: Int = 4

    private let ink = Color(red: 0.024, green: 0.035, blue: 0.055)     // #06090e
    private let warm = Color(red: 0.949, green: 0.910, blue: 0.835)    // #f2e8d5

    var body: some View {
        NavigationStack {
            List {
                Section("Authorization") {
                    HStack {
                        Text("AlarmKit")
                        Spacer()
                        Text(authLabel).foregroundStyle(.secondary)
                    }
                    Button("Request access") { Task { _ = await scheduler.ensureAuthorized() } }
                }

                Section("Test chain") {
                    Stepper(value: $firstSoundInMinutes, in: 1...120, step: 1) {
                        Text("Phase 1 in \(Int(firstSoundInMinutes)) min")
                    }
                    Picker("Gap", selection: $gapMinutes) {
                        Text("1 min (test)").tag(1.0)
                        Text("3").tag(3.0)
                        Text("6").tag(6.0)
                        Text("9").tag(9.0)
                    }
                    Stepper(value: $plateauRepeats, in: 0...20) {
                        Text("Plateau repeats: \(plateauRepeats)")
                    }
                    Text(previewText).font(.footnote).foregroundStyle(.secondary)
                    Button {
                        let plan = ChainPlan.twoPhase(
                            wakeAt: Date().addingTimeInterval(firstSoundInMinutes * 60),
                            gap: gapMinutes * 60,
                            plateauRepeats: plateauRepeats,
                            pairName: "Dawn")
                        Task { await scheduler.schedule(plan) }
                    } label: {
                        Text("Arm chain").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(warm)
                    .foregroundStyle(.black)

                    Button("Cancel everything", role: .destructive) { scheduler.cancelEverything() }
                }

                Section("Armed alarms (\(scheduler.scheduled.count))") {
                    if scheduler.scheduled.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach(scheduler.scheduled, id: \.id) { alarm in
                        HStack {
                            Text(alarm.id.uuidString.prefix(8))
                                .font(.system(.footnote, design: .monospaced))
                            Spacer()
                            Text(describe(alarm)).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Log") {
                    ForEach(scheduler.log, id: \.self) { line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ink)
            .navigationTitle("Fathom · skeleton")
            .toolbar {
                Button("Refresh") { scheduler.refresh() }
            }
        }
        .task { await scheduler.observe() }
        .onAppear { scheduler.refresh() }
    }

    private var authLabel: String {
        switch scheduler.authorization {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "not determined"
        @unknown default: return "unknown"
        }
    }

    private var previewText: String {
        let steps = ChainPlan.escalationOffsets.count + plateauRepeats + 1
        let total = firstSoundInMinutes * 60 + gapMinutes * 60 + (ChainPlan.escalationOffsets.last ?? 0)
            + ChainPlan.plateauInterval * Double(plateauRepeats)
        return "\(steps) alarms · last fires in \(Int(total / 60)) min"
    }

    private func describe(_ alarm: Alarm) -> String {
        if case .fixed(let date)? = alarm.schedule {
            return ChainScheduler.time(date)
        }
        return "\(alarm.state)"
    }
}
