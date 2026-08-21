import SwiftUI

@main
struct FathomApp: App {
    @StateObject private var scheduler = ChainScheduler()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scheduler)
                .preferredColorScheme(.dark)
        }
    }
}
