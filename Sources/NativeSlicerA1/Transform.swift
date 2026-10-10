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

    init(translation: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }

    static let identity = Transform(translation: .zero, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: SIMD3(1, 1, 1))

    /// Decomposes a TRS-only matrix (scale, then rotate, then translate —
    /// the same composition `matrix` produces) back into components. Used
    /// to round-trip a 3MF instance's placement matrix (P1-007) back into
    /// an editable `Transform`. Only valid for matrices actually produced
    /// by that composition (no shear/skew). A reflected basis retains one
    /// negative scale axis; quaternions themselves cannot represent a
    /// reflection, so its column is flipped before constructing rotation.
    init(matrix m: simd_float4x4) {
        translation = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        let c0 = SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)
        let c1 = SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)
        let c2 = SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        let sx = simd_length(c0), sy = simd_length(c1), sz = simd_length(c2)
        var r0 = sx > 0 ? c0 / sx : c0
        let r1 = sy > 0 ? c1 / sy : c1
        let r2 = sz > 0 ? c2 / sz : c2
        var signedScale = SIMD3(sx, sy, sz)
        if simd_dot(simd_cross(r0, r1), r2) < 0 {
            signedScale.x = -sx
            r0 = -r0
        }
        scale = signedScale
        rotation = simd_quatf(simd_float3x3(r0, r1, r2))
    }

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
