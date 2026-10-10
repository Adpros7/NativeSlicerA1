import simd

/// Translation/rotation/scale transform for a scene object. Kept as
/// separate TRS components (not a bare matrix) so the UI can edit each
/// independently and undo/redo can snapshot small value types cheaply —
/// per SPEC.md §9, geometry operations must be stored as editable
/// parameters, not baked into the mesh.
struct Transform: Equatable {
    var translation: SIMD3<Float>
    var rotation: simd_quatf
    var scale: SIMD3<Float>

    static let identity = Transform(translation: .zero, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: SIMD3(1, 1, 1))

    /// Column-major model matrix: scale, then rotate, then translate.
    var matrix: simd_float4x4 {
        let s = simd_float4x4(diagonal: SIMD4(scale.x, scale.y, scale.z, 1))
        let r = simd_float4x4(rotation)
        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4(translation.x, translation.y, translation.z, 1)
        return t * r * s
    }

    func translated(by delta: SIMD3<Float>) -> Transform {
        var copy = self
        copy.translation += delta
        return copy
    }

    func scaled(by factor: SIMD3<Float>) -> Transform {
        var copy = self
        copy.scale *= factor
        return copy
    }

    func rotated(by quaternion: simd_quatf) -> Transform {
        var copy = self
        copy.rotation = quaternion * copy.rotation
        return copy
    }
}
