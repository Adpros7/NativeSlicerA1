import Foundation

/// A placed object in the scene. The source mesh (from P1-004/P1-005
/// import) is referenced by id and never mutated here — only the
/// transform is edited, and every edit is undoable, per SPEC.md §9's
/// non-destructive geometry requirement.
struct SceneObject: Identifiable, Equatable {
    let id: UUID
    let sourceMeshID: UUID
    private var transformHistory: UndoStack<Transform>
    /// P4-014 variable layer height Z-range overrides (object-local Z,
    /// mm). Empty means uniform layer height throughout the object.
    var layerHeightRanges: [LayerHeightRange] = []
    /// P4-007 cut lineage: nonzero shares one value across every part
    /// that came from the same `performCut()`, persisted via
    /// `storeThreeMF`'s `cutGroupIDs` / `loadThreeMFCutGroupID`.
    var cutGroupID: UInt64?
    /// P4-008 batch-job plate grouping — which `Plate.id` this object is
    /// currently placed on.
    var plateID: UInt64
    /// P4-013 local per-volume config override regions (modifier meshes).
    var modifiers: [ModifierPlacement] = []

    init(id: UUID = UUID(), sourceMeshID: UUID, transform: Transform = .identity, cutGroupID: UInt64? = nil, plateID: UInt64) {
        self.id = id
        self.sourceMeshID = sourceMeshID
        transformHistory = UndoStack(initial: transform)
        self.cutGroupID = cutGroupID
        self.plateID = plateID
    }

    /// Compares observable state only, not `transformHistory`'s full
    /// undo depth — two objects with the same id/mesh/transform/ranges
    /// are equal for P4-007's scene-composition `UndoStack` even if one
    /// has more per-object transform undo history than the other (that
    /// history isn't part of what a cut undo/redo needs to restore).
    static func == (lhs: SceneObject, rhs: SceneObject) -> Bool {
        lhs.id == rhs.id && lhs.sourceMeshID == rhs.sourceMeshID &&
            lhs.transform == rhs.transform && lhs.layerHeightRanges == rhs.layerHeightRanges &&
            lhs.cutGroupID == rhs.cutGroupID && lhs.plateID == rhs.plateID && lhs.modifiers == rhs.modifiers
    }

    var transform: Transform { transformHistory.current }
    var canUndo: Bool { transformHistory.canUndo }
    var canRedo: Bool { transformHistory.canRedo }

    mutating func apply(_ newTransform: Transform) {
        transformHistory.push(newTransform)
    }

    mutating func undo() { transformHistory.undo() }
    mutating func redo() { transformHistory.redo() }
}
