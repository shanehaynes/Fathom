import SwiftUI

// §4 Wake — appears when the user engages the firing alarm and the app
// foregrounds. Scene rising with the sound, clock, pair name + phase label,
// and a single warm-white button. Dismissal ends everything. Nothing follows.

struct WakeView: View {
    @Environment(AlarmStore.self) private var store
    let phase2Start: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let m = max(0, timeline.date.timeIntervalSince(phase2Start) / 60)
            let I = Depth.wake(minutesIntoPhase2: m)
            ZStack {
                // On Wake, veil opacity is 1 − 0.45·I (§5) — the water rises
                // toward you as the sound climbs.
                OceanScene(depth: I, veilFactor: 1 - 0.45 * I)

                VStack {
                    Text("Wake").tagStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    Text(timeline.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .font(.clock(72))
                        .foregroundStyle(Theme.textHi)
                    Text("\(pairName) · phase two")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.warm.opacity(0.85))
                        .padding(.top, 10)
                    Text(phaseLabel(minutes: m))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warmDim)
                        .padding(.top, 4)

                    Spacer()

                    Button {
                        Task { await AlarmEngine.shared.dismissActive(store: store) }
                    } label: {
                        Text("I'm up")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.onWarm)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.warm, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
            }
        }
        .onAppear {
            let pair = AlarmEngine.shared.activeChain
                .flatMap { chain in store.alarms.first { $0.id == chain.parentID }?.pair }
                ?? .dawn
            WakeAudio.shared.startWake(pair: pair, phase2Start: phase2Start)
        }
    }

    private var pairName: String {
        AlarmEngine.shared.activeChain
            .flatMap { chain in store.alarms.first { $0.id == chain.parentID }?.pair.name }
            ?? SoundPair.dawn.name
    }

    private func phaseLabel(minutes m: Double) -> String {
        m < 0.5 ? "gentle" : (m < 4 ? "rising" : "full")
    }
}
