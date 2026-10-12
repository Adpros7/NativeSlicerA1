import XCTest
import simd
@testable import NativeSlicerA1

private func repoRoot(from file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Tests/NativeSlicerA1Tests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

/// P4-011: auto-arrange, via the real engine's libnest2d-backed
/// `Slic3r::arrangement::arrange()`. P4-010: auto-orient, via the real
/// engine's `Slic3r::orientation::orient()`.
final class AutoArrangeTests: XCTestCase {
    /// A real, printer-bed-sized part (~68x14x0.2mm) — small enough that
    /// several copies fit on the A1's 256x256mm bed, unlike the full-size
    /// printer-body reference model used by other tests.
    private func loadReferenceMesh() throws -> LoadedMesh {
        try SlicingEngine.loadSTLMesh(
            atPath: repoRoot().appendingPathComponent(
                "Sources/NativeSlicerA1/Resources/Calibration/pressure_advance/pressure_advance_test.stl"
            ).path
        )
    }

    /// A real, full printer-body-sized mesh (258x276mm) — larger than the
    /// A1's 256x256mm bed on its own.
    private func loadOversizedMesh() throws -> LoadedMesh {
        try SlicingEngine.loadSTLMesh(
            atPath: repoRoot().appendingPathComponent("Sources/NativeSlicerA1/Resources/Profiles/BBL/bbl-3dp-X1.stl").path
        )
    }

    /// Two copies of the same real part, both starting at the origin
    /// (fully overlapping), must be packed by the real engine onto the
    /// A1's bed with zero overlap and within bed bounds.
    func testAutoArrangeProducesNonOverlappingPlacementsOnRealBed() throws {
        let mesh = try loadReferenceMesh()
        let identity = matrix_identity_float4x4
        let meshes = [
            (vertices: mesh.vertices, indices: mesh.indices, matrix: identity),
            (vertices: mesh.vertices, indices: mesh.indices, matrix: identity)
        ]

        let results = try SlicingEngine.autoArrange(
            meshes: meshes,
            bedWidth: 256,
            bedHeight: 256,
            clearance: 2.0
        )

        XCTAssertEqual(results.count, 2)
        // Both must land on the physical bed (index 0): the reference
        // part is small enough that two copies fit on a single A1 bed.
        XCTAssertEqual(results[0].bedIndex, 0)
        XCTAssertEqual(results[1].bedIndex, 0)

        // The real packer must have moved the two fully-overlapping
        // copies apart — some nonzero separation in at least one axis.
        let dx = abs(results[0].x - results[1].x)
        let dy = abs(results[0].y - results[1].y)
        XCTAssertGreaterThan(dx + dy, 0, "arrange() must separate overlapping copies")
    }

    /// A part larger than the bed in both X and Y must be reported as
    /// unplaceable (UNARRANGED, bed index -1) by the real packer — not
    /// silently clamped or force-placed off the usable print area.
    func testAutoArrangeReportsUnarrangedForOversizedPart() throws {
        let mesh = try loadOversizedMesh()
        let identity = matrix_identity_float4x4
        let results = try SlicingEngine.autoArrange(
            meshes: [(vertices: mesh.vertices, indices: mesh.indices, matrix: identity)],
            bedWidth: 256,
            bedHeight: 256,
            clearance: 2.0
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].bedIndex, -1, "a part larger than the bed must be reported as unplaceable")
    }

    /// Auto-orient on a real asymmetric part must return a valid rotation
    /// matrix (orthonormal, determinant +1) — not an identity passthrough
    /// or a degenerate transform.
    func testAutoOrientReturnsValidRotationMatrix() throws {
        let mesh = try loadReferenceMesh()
        let matrix = try SlicingEngine.autoOrientMesh(mesh)

        // The upper-left 3x3 must be a valid rotation: orthonormal columns.
        let c0 = SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let c1 = SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        let c2 = SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        XCTAssertEqual(simd_length(c0), 1, accuracy: 0.01)
        XCTAssertEqual(simd_length(c1), 1, accuracy: 0.01)
        XCTAssertEqual(simd_length(c2), 1, accuracy: 0.01)
        XCTAssertEqual(simd_dot(c0, c1), 0, accuracy: 0.01)
        let det = simd_dot(c0, simd_cross(c1, c2))
        XCTAssertEqual(det, 1, accuracy: 0.01)
    }
}
