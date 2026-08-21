import AlarmKit

/// Metadata attached to every system alarm in a wake chain.
/// Shared with the widget extension (compiled into both targets).
struct WakeMetadata: AlarmMetadata {
    /// Identifies the chain this alarm belongs to. Dismissing any member cancels the rest.
    let chainID: String
    /// 0 = phase 1 (gentle). 1...5 = phase 2 files A–E. 6+ = plateau repeats of E.
    let step: Int
    /// Human label shown in the system alert / Live Activity, e.g. "Dawn · gentle".
    let label: String
}
