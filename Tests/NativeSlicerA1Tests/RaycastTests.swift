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

    /// P4-006: connector placement must intersect the actual visible cut
    /// plane, not the selected object's surface. A forward ray intersects
    /// a plane at the exact expected world-space point; a parallel ray
    /// has no stable placement point and is rejected.
    func testRayPlaneIntersectionFindsForwardHitAndRejectsParallelRay() {
        XCTAssertEqual(
            rayPlaneIntersection(
                origin: SIMD3<Float>(2, 3, 10),
                direction: SIMD3<Float>(0, 0, -1),
                planePoint: SIMD3<Float>(0, 0, 4),
                planeNormal: SIMD3<Float>(0, 0, 1)
            ),
            SIMD3<Float>(2, 3, 4)
        )
        XCTAssertNil(rayPlaneIntersection(
            origin: SIMD3<Float>(0, 0, 10),
            direction: SIMD3<Float>(1, 0, 0),
            planePoint: .zero,
            planeNormal: SIMD3<Float>(0, 0, 1)
        ))
    }
}
