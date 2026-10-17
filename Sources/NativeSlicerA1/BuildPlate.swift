import simd

/// Real Bambu Lab A1 build volume — `bed_shape: 0x0,256x0,256x256,0x256`
/// and `printable_height: 256` in the vendored
/// `Resources/Profiles/BBL/machine/Bambu Lab A1 0.4 nozzle.json` profile.
/// Same constant `PlatePreviewView` already uses for its 2D top-down
/// preview; this is the 3D viewport's equivalent always-visible
/// reference geometry.
enum A1BuildVolume {
    static let width: Float = 256
    static let depth: Float = 256
    static let height: Float = 256
}

/// Pure geometry for the viewport's always-visible build plate: an
/// outline rectangle, an interior grid, and short X(red)/Y(green)/
/// Z(blue) axis indicators from the bed origin — plain position+color
/// line segments the existing line-list pipeline already knows how to
/// draw (same vertex layout `CutPlane.wireframeSegments` produces),
/// zero new shaders needed. Generated once; the plate's dimensions never
/// change at runtime (single-printer, A1-only scope per SPEC.md).
enum BuildPlateGeometry {
    struct Segment: Equatable {
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        let color: SIMD3<Float>
    }

    static let plateColor = SIMD3<Float>(0.5, 0.5, 0.55)
    static let gridColor = SIMD3<Float>(0.3, 0.3, 0.34)
    static let xAxisColor = SIMD3<Float>(0.9, 0.2, 0.2)
    static let yAxisColor = SIMD3<Float>(0.2, 0.9, 0.2)
    static let zAxisColor = SIMD3<Float>(0.25, 0.5, 0.95)

    static func segments(
        width: Float = A1BuildVolume.width,
        depth: Float = A1BuildVolume.depth,
        spacing: Float = 10,
        axisLength: Float = 30
    ) -> [Segment] {
        var segments: [Segment] = []

        let corners = [SIMD3<Float>(0, 0, 0), SIMD3(width, 0, 0), SIMD3(width, depth, 0), SIMD3(0, depth, 0)]
        for i in 0..<4 {
            segments.append(Segment(start: corners[i], end: corners[(i + 1) % 4], color: plateColor))
        }

        var x = spacing
        while x < width {
            segments.append(Segment(start: SIMD3(x, 0, 0), end: SIMD3(x, depth, 0), color: gridColor))
            x += spacing
        }
        var y = spacing
        while y < depth {
            segments.append(Segment(start: SIMD3(0, y, 0), end: SIMD3(width, y, 0), color: gridColor))
            y += spacing
        }

        segments.append(Segment(start: .zero, end: SIMD3(axisLength, 0, 0), color: xAxisColor))
        segments.append(Segment(start: .zero, end: SIMD3(0, axisLength, 0), color: yAxisColor))
        segments.append(Segment(start: .zero, end: SIMD3(0, 0, axisLength), color: zAxisColor))

        return segments
    }
}
