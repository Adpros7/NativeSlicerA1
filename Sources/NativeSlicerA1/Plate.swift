import Foundation

/// A batch-job grouping of placed objects (P4-008). The A1 itself is
/// single-bed hardware (FEATURE_PARITY.md §3/§5/§7) — a "plate" here is
/// an app-level concept (independent object subset, independent
/// slice/arrange/export), not simultaneous multi-bed hardware. Matches
/// BambuStudio's `PartPlate` naming for the same real-world workflow:
/// queue several builds, arrange/slice/export each in turn.
///
/// `id` is `UInt64` (not `UUID`) so it round-trips through the same
/// plain-scalar 3MF custom-archive-entry mechanism P4-007's
/// `cutGroupID` already uses, without a UUID<->scalar mapping layer.
struct Plate: Identifiable, Equatable {
    let id: UInt64
    var name: String

    init(id: UInt64 = .random(in: 1...UInt64.max), name: String) {
        self.id = id
        self.name = name
    }
}
