import simd

/// An interactive cut plane in WORLD space — matching the real engine's
/// `ModelObject::cut` convention that `plane_points` are world-space,
/// subtracted by the target instance's own offset internally (see
/// `SlicingEngine.cutModel`'s doc comment). Default normal is world +Z,
/// matching the slicing engine's own height axis (bed at Z=0, G-code Z
/// is print height — the same convention `LayerHeightRange`/`CutModel`
/// already use), independent of the viewport camera's Y-up rendering.
struct CutPlane: Equatable {
    var center: SIMD3<Float>
    /// Tilt around world X, radians. 0 = flat/horizontal cut.
    var tiltX: Float = 0
    /// Tilt around world Y, radians.
    var tiltY: Float = 0
    /// Half-extent (mm) of the plane quad — must exceed the target
    /// object's own footprint for a valid, fully-intersecting cut.
    var halfExtent: Float = 100

    private var orientation: simd_quatf {
        simd_quatf(angle: tiltY, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: tiltX, axis: SIMD3(1, 0, 0))
    }

    var normal: SIMD3<Float> { simd_act(orientation, SIMD3(0, 0, 1)) }

    private var basis: (u: SIMD3<Float>, v: SIMD3<Float>) {
        let o = orientation
        return (simd_act(o, SIMD3(1, 0, 0)), simd_act(o, SIMD3(0, 1, 0)))
    }

    private var corners: [SIMD3<Float>] {
        let (u, v) = basis
        return [
            center - u * halfExtent - v * halfExtent,
            center + u * halfExtent - v * halfExtent,
            center + u * halfExtent + v * halfExtent,
            center - u * halfExtent + v * halfExtent,
        ]
    }

    /// The 4 real-world corner points `SlicingEngine.cutModel` consumes
    /// directly as its `planePoints` argument.
    var planePoints: [(Float, Float, Float)] {
        corners.map { ($0.x, $0.y, $0.z) }
    }

    /// Line-segment endpoints for rendering: the quad outline (4 edges)
    /// plus a short normal indicator from the center, as flat position
    /// triples ready for the viewport's existing line-list pipeline.
    var wireframeSegments: [(SIMD3<Float>, SIMD3<Float>)] {
        let c = corners
        var segments: [(SIMD3<Float>, SIMD3<Float>)] = (0..<4).map { (c[$0], c[($0 + 1) % 4]) }
        segments.append((center, center + normal * (halfExtent * 0.3)))
        return segments
    }

    /// Places a real upstream connector mesh (whose local generator
    /// convention is z=0...height) symmetrically across this plane:
    /// local +Z aligns with the plane normal and its z=height/2 midpoint
    /// is exactly at the clicked plane point. Used by the Metal preview;
    /// the same world point/normal are converted to the C-ABI connector
    /// request at cut time.
    func connectorTransform(at position: SIMD3<Float>, preset: ConnectorPreset) -> simd_float4x4 {
        let rotation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: normal)
        var transform = simd_float4x4(rotation)
        let offset = position - normal * (preset.height * 0.5)
        transform.columns.3 = SIMD4(offset.x, offset.y, offset.z, 1)
        return transform
    }
}
