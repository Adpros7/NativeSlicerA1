import CSlic3rBridge
import Foundation

/// Support-paint brush type (P3-005), matching the real engine's
/// `Slic3r::EnforcerBlockerType` (`NSA1EnforcerBlockerType` in the C-ABI).
enum SupportPaintType: Int32 {
    case none = 0
    case enforcer = 1
    case blocker = 2
}

/// Wraps one mesh's real `Slic3r::TriangleSelector`-backed paint-editing
/// session (P3-005). Non-destructive: paints a copy of the mesh data the
/// handle owns, never touches the original `LoadedMesh`. Owns the native
/// handle and frees it on deinit.
final class SupportPaintState {
    private var handle: OpaquePointer?
    private var history: UndoStack<[UInt8]>

    /// Creates a paint session for `mesh`'s local (un-instance-transformed)
    /// geometry, via the real engine's `nsa1_paint_create`.
    init?(mesh: LoadedMesh) {
        let created = mesh.vertices.withUnsafeBufferPointer { vbuf in
            mesh.indices.withUnsafeBufferPointer { ibuf in
                nsa1_paint_create(vbuf.baseAddress, vbuf.count / 3, ibuf.baseAddress, ibuf.count)
            }
        }
        guard let created else { return nil }
        handle = created
        history = UndoStack(initial: [])
    }

    deinit {
        if let handle {
            nsa1_paint_free(handle)
        }
    }

    /// Paints a spherical brush stroke at `center` (local mesh coordinates,
    /// mm) with `radius` (mm), via the real engine's
    /// `TriangleSelector::select_patch`. Each stroke is one undo snapshot.
    func paintSphere(center: SIMD3<Float>, radius: Float, type: SupportPaintType) {
        guard let handle else { return }
        nsa1_paint_sphere(
            handle,
            Double(center.x), Double(center.y), Double(center.z),
            Double(radius),
            type.rawValue
        )
        history.push(serialize())
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    @discardableResult
    func undo() -> Bool {
        guard canUndo else { return false }
        return restore(history.undo())
    }

    @discardableResult
    func redo() -> Bool {
        guard canRedo else { return false }
        return restore(history.redo())
    }

    /// Serializes the current paint state to the real engine's own
    /// `TriangleSelector::serialize()` wire format (opaque to Swift —
    /// round-trips through `SlicingEngine.sliceToGCode`'s `paintData`).
    func serialize() -> [UInt8] {
        guard let handle else { return [] }
        var dataPtr: UnsafeMutablePointer<UInt8>?
        var size: Int = 0
        nsa1_paint_serialize(handle, &dataPtr, &size)
        guard let dataPtr, size > 0 else { return [] }
        defer { nsa1_paint_data_free(dataPtr) }
        return Array(UnsafeBufferPointer(start: dataPtr, count: size))
    }

    /// Restores paint annotations previously serialized by the real
    /// TriangleSelector (for 3MF project reload), replacing this session's
    /// undo history with the loaded state.
    @discardableResult
    func deserialize(_ data: [UInt8]) -> Bool {
        guard restore(data) else { return false }
        history = UndoStack(initial: data)
        return true
    }

    private func restore(_ data: [UInt8]) -> Bool {
        guard let handle else { return false }
        return data.withUnsafeBufferPointer {
            nsa1_paint_deserialize(handle, $0.baseAddress, $0.count) == 0
        }
    }
}
