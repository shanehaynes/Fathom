import SwiftUI

// §4 Alarm — the daytime screen, the one place the spectrum is fully visible
// (day depth 0.85). The full settings surface, top to bottom: time, sound pair,
// day dots, gap, bedside toggle, sunrise lamp (v2). Nothing else earns a
// control (principle 6).

struct AlarmSettingsView: View {
    @Environment(AlarmStore.self) private var store
    /// Slides back out to Tonight (swipe right, or Done).
    var onDone: () -> Void = {}
    @State private var showPicker = false
    @State private var previewing: String?

    private var alarm: AlarmModel {
        store.alarms.first ?? AlarmModel(hour: 6, minute: 10, days: [])
    }

    var body: some View {
        ZStack {
            OceanScene(depth: Depth.day)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Alarm").tagStyle()
                        Spacer()
                        Button("Done") { onDone() }
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.warm)
                    }

                    // Time — large numerals, wheel picker on tap.
                    HStack {
                        Spacer()
                        Button {
                            showPicker.toggle()
                        } label: {
                            Text(alarm.timeText)
                                .font(.clock(56))
                                .foregroundStyle(Theme.textHi)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    if showPicker {
                        TimeWheel(alarm: alarm) { updated in
                            commit(updated)
                        }
                    }

                    // Armed toggle
                    card {
                        Toggle(isOn: Binding(
                            get: { alarm.isEnabled },
                            set: { var a = alarm; a.isEnabled = $0; commit(a) }
                        )) {
                            Text("Armed")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textHi)
                        }
                        .tint(Theme.warm.opacity(0.7))
                    }

                    // Sound pairs — tap to preview: 5 s gentle → crossfade → 5 s firm.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sound").tagStyle()
                        ForEach(SoundPair.all) { pair in
                            PairCard(
                                pair: pair,
                                selected: alarm.pairID == pair.id,
                                previewing: previewing == pair.id
                            ) {
                                var a = alarm
                                a.pairID = pair.id
                                commit(a)
                                previewing = pair.id
                                WakeAudio.shared.preview(pair: pair)
                                Task {
                                    try? await Task.sleep(for: .seconds(11))
                                    if previewing == pair.id { previewing = nil }
                                }
                            }
                        }
                    }

                    // Day dots — M T W T F S S.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Days").tagStyle()
                        HStack(spacing: 8) {
                            ForEach(Array(Weekday.displayOrder.enumerated()), id: \.offset) { _, day in
                                DayDot(letter: day.letter, on: alarm.days.contains(day)) {
                                    var a = alarm
                                    if a.days.contains(day) { a.days.remove(day) } else { a.days.insert(day) }
                                    commit(a)
                                }
                            }
                        }
                        if alarm.days.isEmpty {
                            Text("no days — one-shot, then disarms")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textLow)
                        }
                    }

                    // Gap — chosen the night before, with intention (principle 1).
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gap between phases").tagStyle()
                        HStack(spacing: 8) {
                            ForEach([3, 6, 9], id: \.self) { g in
                                GapPill(minutes: g, on: alarm.gapMinutes == g) {
                                    var a = alarm
                                    a.gapMinutes = g
                                    commit(a)
                                }
                            }
                        }
                    }

                    // Bedside mode
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: Binding(
                                get: { store.settings.bedsideMode },
                                set: { store.settings.bedsideMode = $0 }
                            )) {
                                Text("Stay on while charging")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textHi)
                            }
                            .tint(Theme.warm.opacity(0.7))
                            if store.settings.bedsideMode {
                                Toggle(isOn: Binding(
                                    get: { store.settings.redShift },
                                    set: { store.settings.redShift = $0 }
                                )) {
                                    Text("Red shift")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.textHi)
                                }
                                .tint(Theme.warm.opacity(0.7))
                            }
                        }
                    }

                    // Sunrise lamp — v2 (§8). The toggle persists; nothing acts on it yet.
                    card {
                        Toggle(isOn: Binding(
                            get: { store.settings.sunriseLamp },
                            set: { store.settings.sunriseLamp = $0 }
                        )) {
                            HStack {
                                Text("Sunrise lamp")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textMid)
                                Text("v2").tagStyle()
                            }
                        }
                        .tint(Theme.warm.opacity(0.7))
                        .disabled(true)
                    }
                }
                .padding(24)
            }
        }
        .onDisappear { WakeAudio.shared.stop() }
        // Swipe right slides back to Tonight. Simultaneous so the vertical
        // ScrollView keeps its drags; only a horizontally-dominant swipe fires.
        .simultaneousGesture(
            DragGesture(minimumDistance: 25).onEnded { v in
                if v.translation.width > 60,
                   abs(v.translation.width) > abs(v.translation.height) {
                    onDone()
                }
            }
        )
    }

    /// Editing an armed alarm cancels and reschedules its entire chain
    /// atomically (§3).
    private func commit(_ updated: AlarmModel) {
        store.update(updated)
        Task { await AlarmEngine.shared.rescheduleAll(store: store) }
    }

    /// Controls float on translucent ink so they hold against the bright scene (§4).
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(Theme.cardInk, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
    }
}

private struct TimeWheel: View {
    let alarm: AlarmModel
    let commit: (AlarmModel) -> Void

    var body: some View {
        DatePicker(
            "Time",
            selection: Binding(
                get: {
                    Calendar.current.date(
                        bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Date()
                    ) ?? Date()
                },
                set: { date in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                    var a = alarm
                    a.hour = c.hour ?? a.hour
                    a.minute = c.minute ?? a.minute
                    commit(a)
                }
            ),
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .colorScheme(.dark)
        .background(Theme.cardInk, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PairCard: View {
    let pair: SoundPair
    let selected: Bool
    let previewing: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: previewing ? "speaker.wave.2.fill" : "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(selected ? Theme.warm : Theme.textLow)
                    Text(pair.name)
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? Theme.warm : Theme.textMid)
                }
                Text(pair.description)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? Theme.textMid : Theme.textLow)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Theme.cardInk, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Theme.warm.opacity(0.45) : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DayDot: View {
    let letter: String
    let on: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            Text(letter)
                .font(.system(size: 12))
                .foregroundStyle(on ? Theme.warm : Theme.textLow)
                .frame(width: 32, height: 32)
                .background(on ? Theme.warm.opacity(0.14) : .clear, in: Circle())
                .overlay(Circle().stroke(on ? Theme.warm.opacity(0.6) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct GapPill: View {
    let minutes: Int
    let on: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            Text("\(minutes)")
                .font(.system(size: 13))
                .foregroundStyle(on ? Theme.warm : Theme.textLow)
                .padding(.vertical, 6)
                .padding(.horizontal, 18)
                .background(on ? Theme.warm.opacity(0.14) : .clear, in: Capsule())
                .overlay(Capsule().stroke(on ? Theme.warm.opacity(0.6) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
