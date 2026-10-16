import XCTest
import CSlic3rBridge
@testable import NativeSlicerA1
/// P4-005: verifies the 4 real `CutConnectorType` mesh generators
/// (`ModelObject::get_connector_mesh` via `nsa1_make_connector_mesh`)
/// produce real geometry whose dimensions match the requested
/// radius/height, and that tolerance widens the hole-side mesh exactly as
/// upstream's `apply_tolerance` (CutUtils.cpp) does.
final class ConnectorTests: XCTestCase {
    private func boundingBox(_ mesh: LoadedMesh) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var i = 0
        while i < mesh.vertices.count {
            let v = SIMD3<Float>(mesh.vertices[i], mesh.vertices[i + 1], mesh.vertices[i + 2])
            lo = SIMD3(x: Swift.min(lo.x, v.x), y: Swift.min(lo.y, v.y), z: Swift.min(lo.z, v.z))
            hi = SIMD3(x: Swift.max(hi.x, v.x), y: Swift.max(hi.y, v.y), z: Swift.max(hi.z, v.z))
            i += 3
        }
        return (lo, hi)
    }

    func testAllFourConnectorTypesProduceRealNonEmptyMeshes() throws {
        for type in ConnectorType.allCases {
            let preset = ConnectorPreset(type: type, style: .prizm, shape: .circle, radius: 5, height: 10)
            let mesh = try ConnectorMeshGenerator.generate(preset, forHole: false)
            XCTAssertGreaterThan(mesh.vertices.count, 0, "\(type) produced an empty mesh")
            XCTAssertGreaterThan(mesh.triangleCount, 0, "\(type) produced no triangles")
            // Every generator must respect the requested radius/height
            // scale, modulo the Snap connector's real "bulge" geometry
            // (its_make_snap's default bulge_proportion=0.15 deliberately
            // makes its middle ring wider than the nominal radius so the
            // snap mechanically catches — not a bug, verified against the
            // real engine's own CutConnectorParas default).
            let (lo, hi) = boundingBox(mesh)
            let xyLimit: Float = type == .snap ? 10 * 1.2 : 10.01
            XCTAssertLessThanOrEqual(hi.x - lo.x, xyLimit, "\(type) exceeded requested XY diameter")
            XCTAssertLessThanOrEqual(hi.y - lo.y, xyLimit, "\(type) exceeded requested XY diameter")
            XCTAssertLessThanOrEqual(hi.z - lo.z, 10.01, "\(type) exceeded requested height")
        }
    }

    /// `its_make_cylinder` (Plug/Prizm) is the simplest generator: a
    /// right cylinder of exact radius/height, centered on the Z axis with
    /// its base at z=0 — verify the exact dimensions, not just bounds.
    func testPlugPrizmMatchesExactCylinderDimensions() throws {
        let preset = ConnectorPreset(type: .plug, style: .prizm, shape: .circle, radius: 5, height: 10)
        let mesh = try ConnectorMeshGenerator.generate(preset, forHole: false)
        let (lo, hi) = boundingBox(mesh)
        XCTAssertEqual(hi.x - lo.x, 10, accuracy: 0.01)
        XCTAssertEqual(hi.y - lo.y, 10, accuracy: 0.01)
        XCTAssertEqual(lo.z, 0, accuracy: 0.01)
        XCTAssertEqual(hi.z, 10, accuracy: 0.01)
    }

    /// Reference dimension check: doubling the requested radius/height
    /// must double the real generated mesh's bounding box exactly
    /// (the engine's own linear scale-factor transform, not an
    /// approximation).
    func testConnectorDimensionsScaleLinearlyWithRadiusAndHeight() throws {
        let small = try ConnectorMeshGenerator.generate(
            ConnectorPreset(type: .plug, style: .prizm, shape: .circle, radius: 3, height: 6), forHole: false)
        let big = try ConnectorMeshGenerator.generate(
            ConnectorPreset(type: .plug, style: .prizm, shape: .circle, radius: 6, height: 12), forHole: false)
        let (sLo, sHi) = boundingBox(small)
        let (bLo, bHi) = boundingBox(big)
        XCTAssertEqual((bHi.x - bLo.x) / (sHi.x - sLo.x), 2, accuracy: 0.001)
        XCTAssertEqual((bHi.z - bLo.z) / (sHi.z - sLo.z), 2, accuracy: 0.001)
    }

    /// `apply_tolerance` (CutUtils.cpp) widens the hole-side connector's
    /// XY scale by `radius_tolerance` and Z scale by `height_tolerance`,
    /// additively on top of the base radius/height — verify the real
    /// engine call reflects that, not a reimplementation.
    func testHoleToleranceWidensRealGeneratedMesh() throws {
        let preset = ConnectorPreset(
            type: .plug, style: .prizm, shape: .circle,
            radius: 5, height: 10, radiusTolerance: 0.5, heightTolerance: 1.0)
        let peg = try ConnectorMeshGenerator.generate(preset, forHole: false)
        let hole = try ConnectorMeshGenerator.generate(preset, forHole: true)
        let (pLo, pHi) = boundingBox(peg)
        let (hLo, hHi) = boundingBox(hole)
        XCTAssertEqual(hHi.x - hLo.x, (pHi.x - pLo.x) + 2 * 0.5, accuracy: 0.01)
        XCTAssertEqual(hHi.z - hLo.z, (pHi.z - pLo.z) + 1.0, accuracy: 0.01)
    }

    func testDowelUsesFrustumDowelGenerator() throws {
        // Dowel always uses its_make_frustum_dowel regardless of style
        // (ModelObject::get_connector_mesh's style check is skipped for
        // Dowel once type==Dowel && style!=Prizm falls through to the
        // frustum_dowel branch) — verify both styles produce geometry.
        for style in ConnectorStyle.allCases {
            let preset = ConnectorPreset(type: .dowel, style: style, shape: .circle, radius: 4, height: 8)
            let mesh = try ConnectorMeshGenerator.generate(preset, forHole: false)
            XCTAssertGreaterThan(mesh.triangleCount, 0)
        }
    }

    func testInvalidEnumValueThrows() {
        // Directly probe the C-ABI's own range validation (negative/
        // out-of-range type) rather than constructing an invalid
        // ConnectorType, which the Swift enum cannot represent.
        XCTAssertNil(nsa1_make_connector_mesh(99, 0, 0, 5, 10, 0, 0, 0))
    }
}
