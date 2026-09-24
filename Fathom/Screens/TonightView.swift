import SwiftUI
import UIKit
import Combine

// §4 Tonight — the resting state. Near-black, spectrum asleep at night depth,
// large thin clock numerals, next-wake line, and one action: Wind down.
// Nothing here rewards opening the app during the day (principle 4).

struct TonightView: View {
    @Environment(AlarmStore.self) private var store
    @State private var windingDown = false
    @State private var showSettings = false
    @State private var isCharging = false

    var body: some View {
        ZStack {
            OceanScene(
                depth: Depth.night,
                mode: store.settings.redShift && store.settings.bedsideMode ? .redShift : .normal,
                slowUpdates: store.settings.bedsideMode && isCharging,
                pixelDrift: store.settings.bedsideMode && isCharging
            )

            VStack {
                HStack {
                    Text("Tonight").tagStyle()
                    Spacer()
                    Button("Alarm") { openSettings() }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textLow)
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(timeline.date, format: Clock.hhmm)
                        .font(.clock(72))
                        .foregroundStyle(Theme.textHi)
                }
                if let next = store.nextWake {
                    Text(wakeLine(next.alarm, at: next.date))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMid)
                        .padding(.top, 10)
                    Text("\(next.alarm.pair.name) · gentle, then firm")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.warm.opacity(0.8))
                        .padding(.top, 2)
                } else {
                    Text("no alarm set")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMid)
                        .padding(.top, 10)
                }

                Spacer()

                Button {
                    if windingDown {
                        WakeAudio.shared.stop()
                        windingDown = false
                    } else {
                        let pair = store.nextWake?.alarm.pair ?? .dawn
                        WakeAudio.shared.startWindDown(pair: pair)
                        windingDown = true
                    }
                } label: {
                    Text(windingDown ? "Winding down…" : "Wind down")
                        .font(.system(size: 15))
                        .foregroundStyle(windingDown ? Theme.warm : Theme.textHi)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.ink2.opacity(0.45), in: Capsule())
                        .overlay(Capsule().stroke(windingDown ? Theme.warm.opacity(0.6) : Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(24)

            // Bedside auto-dim below system brightness (§4 OLED mitigations).
            if store.settings.bedsideMode && isCharging {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Alarm slides in from the right on a leftward swipe and back out
            // on a rightward one — the two screens share the one water.
            if showSettings {
                AlarmSettingsView(onDone: closeSettings)
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }
        }
        // Swipe left pulls up Alarm (the next page sits to the right, as in a
        // pager).
        .gesture(
            DragGesture(minimumDistance: 25).onEnded { v in
                if v.translation.width < -60,
                   abs(v.translation.width) > abs(v.translation.height),
                   !showSettings {
                    openSettings()
                }
            }
        )
        .onAppear { updateCharging() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateCharging()
        }
        // Bedside "stay on while charging": idle timer disabled only while
        // plugged in and on this screen (§4).
        .onChange(of: chargingAndBedside, initial: true) { _, on in
            UIApplication.shared.isIdleTimerDisabled = on
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // "wake at 17:13" when it is tonight; "wake Monday at 17:13" when the next
    // fire is more than ~20 h out, so a weekday-only alarm set on a Saturday
    // cannot read as "today".
    private func wakeLine(_ alarm: AlarmModel, at date: Date) -> String {
        if date.timeIntervalSinceNow > 20 * 3600 {
            let day = date.formatted(.dateTime.weekday(.wide))
            return "wake \(day) at \(alarm.timeText)"
        }
        return "wake at \(alarm.timeText)"
    }

    private func openSettings() {
        withAnimation(.easeInOut(duration: 0.35)) { showSettings = true }
    }

    private func closeSettings() {
        withAnimation(.easeInOut(duration: 0.35)) { showSettings = false }
    }

    private var chargingAndBedside: Bool {
        store.settings.bedsideMode && isCharging
    }

    private func updateCharging() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        isCharging = state == .charging || state == .full
    }
}
