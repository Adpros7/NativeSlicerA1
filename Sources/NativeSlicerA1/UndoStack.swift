/// Generic snapshot-based undo/redo stack. Snapshotting whole `State`
/// values (rather than inverse commands) is the lazy-correct choice here:
/// `Transform` and similar editable-parameter states are small value types,
/// so there's no cost pressure to implement command-pattern undo.
struct UndoStack<State: Equatable> {
    private var history: [State]
    private var cursor: Int // index of the current state in `history`

    init(initial: State) {
        history = [initial]
        cursor = 0
    }

    var current: State { history[cursor] }
    var canUndo: Bool { cursor > 0 }
    var canRedo: Bool { cursor < history.count - 1 }

    /// Records a new state as the current one. Any redo history beyond the
    /// cursor is discarded, matching standard editor undo semantics.
    mutating func push(_ state: State) {
        guard state != history[cursor] else { return }
        history.removeSubrange((cursor + 1)...)
        history.append(state)
        cursor += 1
    }

    @discardableResult
    mutating func undo() -> State {
        if canUndo { cursor -= 1 }
        return current
    }

    @discardableResult
    mutating func redo() -> State {
        if canRedo { cursor += 1 }
        return current
    }
}
