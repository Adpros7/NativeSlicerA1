import Foundation

/// A placed object in the scene. The source mesh (from P1-004/P1-005
/// import) is referenced by id and never mutated here — only the
/// transform is edited, and every edit is undoable, per SPEC.md §9's
/// non-destructive geometry requirement.
struct SceneObject: Identifiable {
    let id: UUID
    let sourceMeshID: UUID
    private var transformHistory: UndoStack<Transform>
    /// P4-014 variable layer height Z-range overrides (object-local Z,
    /// mm). Empty means uniform layer height throughout the object.
    var layerHeightRanges: [LayerHeightRange] = []

    init(id: UUID = UUID(), sourceMeshID: UUID, transform: Transform = .identity) {
        self.id = id
        self.sourceMeshID = sourceMeshID
        transformHistory = UndoStack(initial: transform)
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
