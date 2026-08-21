import WidgetKit
import SwiftUI
import ActivityKit
import AlarmKit

/// Minimal Live Activity for the wake chain. AlarmKit uses this for the Dynamic Island
/// and lock-screen presentation while an alarm is alerting. Deliberately plain for
/// milestone 1 — the real scene (DESIGN.md §5) comes in milestone 2.
@main
struct FathomWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WakeLiveActivity()
    }
}

struct WakeLiveActivity: Widget {
    private let warm = Color(red: 0.949, green: 0.910, blue: 0.835)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeMetadata>.self) { context in
            HStack {
                Image(systemName: "sun.horizon")
                Text(context.attributes.metadata?.label ?? "Fathom")
                Spacer()
            }
            .foregroundStyle(warm)
            .padding()
            .activityBackgroundTint(Color(red: 0.024, green: 0.035, blue: 0.055))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.metadata?.label ?? "Fathom").foregroundStyle(warm)
                }
            } compactLeading: {
                Image(systemName: "sun.horizon").foregroundStyle(warm)
            } compactTrailing: {
                Text("").foregroundStyle(warm)
            } minimal: {
                Image(systemName: "sun.horizon").foregroundStyle(warm)
            }
        }
    }
}
