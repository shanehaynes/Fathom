import WidgetKit
import SwiftUI
import ActivityKit
import AlarmKit

// Live Activity for the wake chain. AlarmKit renders this on the lock screen
// and in the Dynamic Island while a chain member is alerting. Colors mirror
// Theme.swift by value — the extension does not compile the app's Theme.

@main
struct FathomWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WakeLiveActivity()
    }
}

struct WakeLiveActivity: Widget {
    private let warm = Color(red: 0xF2 / 255, green: 0xE8 / 255, blue: 0xD5 / 255)
    private let textMid = Color(red: 0x7E / 255, green: 0x8E / 255, blue: 0xA0 / 255)
    private let ink = Color(red: 0x06 / 255, green: 0x09 / 255, blue: 0x0E / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<FathomMetadata>.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "sun.horizon")
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.metadata?.label ?? "Fathom")
                    Text("stop is \"I'm up\" — no snooze")
                        .font(.system(size: 12))
                        .foregroundStyle(textMid)
                }
                Spacer()
            }
            .foregroundStyle(warm)
            .padding()
            .activityBackgroundTint(ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.metadata?.label ?? "Fathom")
                        .foregroundStyle(warm)
                }
            } compactLeading: {
                Image(systemName: "sun.horizon").foregroundStyle(warm)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "sun.horizon").foregroundStyle(warm)
            }
        }
    }
}
