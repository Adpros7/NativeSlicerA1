import XCTest
import simd
@testable import NativeSlicerA1

final class RaycastTests: XCTestCase {
    private func singleTriangle() -> LoadedMesh {
        LoadedMesh(
            vertices: [
                -1, -1, 0,
                 1, -1, 0,
                 0,  1, 0,
            ],
            indices: [0, 1, 2]
        )
    }

    /// P3-005: the viewport's local-space Möller–Trumbore hit test finds
    /// a front-facing mesh triangle at the actual intersection point.
    func testRayMeshIntersectionHitsTriangle() throws {
        let hit = rayMeshIntersection(
            origin: SIMD3<Float>(0, 0, 5),
            direction: SIMD3<Float>(0, 0, -1),
            mesh: singleTriangle()
        )
        let point = try XCTUnwrap(hit)
        XCTAssertEqual(point.x, 0, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0, accuracy: 0.0001)
        XCTAssertEqual(point.z, 0, accuracy: 0.0001)
    }

    /// A ray outside the triangle must not paint a false-positive region.
    func testRayMeshIntersectionMissesOutsideTriangle() {
        XCTAssertNil(rayMeshIntersection(
            origin: SIMD3<Float>(5, 5, 5),
            direction: SIMD3<Float>(0, 0, -1),
            mesh: singleTriangle()
        ))
    }
}
