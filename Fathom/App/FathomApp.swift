import SwiftUI

@main
struct FathomApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AlarmStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)   // single committed dark theme (§5)
                .statusBarHidden()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in
                let engine = AlarmEngine.shared
                engine.refreshPhase()
                // Fixed-date chains are rescheduled on every foreground — but
                // never while a chain is in flight, which would cancel a firing
                // alarm (§3: dismissal is the only thing that ends a chain).
                if !engine.phase.isRinging {
                    await BackupChain.requestAuthorization()
                    await engine.rescheduleAll(store: AlarmStore.shared)
                }
            }
        }
    }
}

struct RootView: View {
    @State private var engine = AlarmEngine.shared

    var body: some View {
        Group {
            switch engine.phase {
            case .phase2(let started):
                WakeView(phase2Start: started)
            case .phase1Playing, .gapWaiting:
                // Engaged before phase 2 — Wake with the ramp not yet begun.
                // Dismissing here provably cancels phase 2 (§3).
                WakeView(phase2Start: phase2Date)
            default:
                TonightView()
            }
        }
        .background(Theme.ink)
    }

    private var phase2Date: Date {
        if case .gapWaiting(let at) = engine.phase { return at }
        return engine.activeChain?.phase2At ?? Date().addingTimeInterval(360)
    }
}
