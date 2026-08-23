import WidgetKit
import SwiftUI
import ActivityKit
import AlarmKit

// Live Activity for the wake chain — the lock-screen and Dynamic Island
// presentation while a chain member alerts. A widget cannot animate, but it
// can carry the §5 scene as a snapshot at the alerting member's depth, so the
// light is on the lock screen even when the app is not.

@main
struct FathomWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WakeLiveActivity()
    }
}

struct WakeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<FathomMetadata>.self) { context in
            LockScreenWake(metadata: context.attributes.metadata)
                .activityBackgroundTint(Theme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    LockScreenWake(metadata: context.attributes.metadata, compact: true)
                }
            } compactLeading: {
                Image(systemName: "sun.horizon").foregroundStyle(Theme.warm)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "sun.horizon").foregroundStyle(Theme.warm)
            }
        }
    }
}

/// The scene at the depth of the member that is alerting, label over it.
struct LockScreenWake: View {
    let metadata: FathomMetadata?
    var compact = false

    var body: some View {
        let I = depth
        ZStack(alignment: .leading) {
            Canvas { context, size in
                drawOcean(in: &context, size: size, t: t, depth: I,
                          veilFactor: 1 - 0.45 * I, blooms: blooms)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(metadata?.label ?? "Fathom")
                    .font(.system(size: compact ? 14 : 17, weight: .medium))
                    .foregroundStyle(Theme.warm)
                if !compact {
                    Text("stop is \"I'm up\" — no snooze")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMid)
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: compact ? 60 : 130)
    }

    /// Phase 1 stirs; A opens at day depth (§5) and each step rises toward full.
    private var depth: Double {
        switch metadata?.role {
        case "phase1": return Depth.stirring
        case "a": return Depth.day
        case "b": return 0.89
        case "c": return 0.93
        case "d": return 0.97
        default: return 1.0          // e, e-repeat-N
        }
    }

    /// One composition per chain, so successive members do not reshuffle the light.
    private var blooms: [Bloom] {
        let u = metadata?.parentID.uuid
        let seed = u.map { Double(Int($0.0) << 8 | Int($0.1)) / 65536 } ?? 0.4
        return Bloom.make(seed: seed)
    }

    /// Each member's snapshot sits a little further along the drift.
    private var t: Double {
        (metadata.map { Date().timeIntervalSince($0.phase2Start) } ?? 0) * 1000
    }
}
