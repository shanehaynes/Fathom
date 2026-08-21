import AppIntents
import AlarmKit

/// The "I'm up" action. Wired as the `stopIntent` of every alarm in a chain, so
/// tapping the system alert's stop button on ANY phase cancels everything downstream —
/// dismissing phase 1 means phase 2 never fires (DESIGN.md §3).
///
/// LiveActivityIntents run in the app's process; the app is launched in the
/// background if needed. `openAppWhenRun = false`: nothing should follow "I'm up".
struct ImUpIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "I'm up"
    static var description = IntentDescription("Ends the wake and cancels the rest of the chain.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Chain ID")
    var chainID: String

    init() { chainID = "" }
    init(chainID: String) { self.chainID = chainID }

    func perform() async throws -> some IntentResult {
        ChainStore.cancelChain(id: chainID)
        return .result()
    }
}
