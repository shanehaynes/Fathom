import AlarmKit
import Foundation

/// Metadata attached to every system alarm in a wake chain. Compiled into both
/// the app and the FathomWidgets extension, so it must not depend on anything
/// app-only (Theme, stores, engine).
struct FathomMetadata: AlarmMetadata {
    let parentID: UUID
    let role: String          // "phase1", "a"..."e", "e-repeat-N"
    let phase2Start: Date
    /// Shown in the Live Activity / Dynamic Island, e.g. "Dawn · gentle".
    let label: String
}
