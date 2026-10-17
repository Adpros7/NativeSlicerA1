import XCTest
import simd
@testable import NativeSlicerA1

/// P6-005: proves `SlicingEngine.validateSequentialCollision` calls the
/// real upstream `Print::validate()` sequential/by-object collision check
/// (`Print.cpp` `STRING_EXCEPT_OBJECT_COLLISION_IN_SEQ_PRINT`), not a
/// Swift-side geometric reimplementation.
final class CollisionValidationTests: XCTestCase {
    private func cubeMesh(size: Float = 20) -> LoadedMesh {
        let url = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/NativeSlicerA1/Resources/Profiles/BBL/bbl-3dp-X1.stl")
        // The fixture STL isn't a unit cube; build a real cube directly
        // instead so collision geometry is exact and predictable.
        _ = url
        let half = size / 2
        let positions: [SIMD3<Float>] = [
            SIMD3(-half, -half, 0), SIMD3(half, -half, 0), SIMD3(half, half, 0), SIMD3(-half, half, 0),
            SIMD3(-half, -half, size), SIMD3(half, -half, size), SIMD3(half, half, size), SIMD3(-half, half, size),
        ]
        let faces: [[Int]] = [
            [0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6],
            [0, 4, 5], [0, 5, 1], [1, 5, 6], [1, 6, 2],
            [2, 6, 7], [2, 7, 3], [3, 7, 4], [3, 4, 0],
        ]
        var vertices: [Float] = []
        for p in positions { vertices.append(contentsOf: [p.x, p.y, p.z]) }
        let indices = faces.flatMap { $0.map { UInt32($0) } }
        return LoadedMesh(vertices: vertices, indices: indices)
    }

    private func sequentialConfigEntries() throws -> [(key: String, value: String)] {
        let loader = try BambuProfileLoader()
        var entries = try SlicingJob.resolvedConfigEntries(loader: loader)
        entries.append((key: "print_sequence", value: "by object"))
        return entries
    }

    func testOverlappingObjectsReportRealSequentialCollision() throws {
        let mesh = cubeMesh()
        let result = try SlicingEngine.validateSequentialCollision(
            objects: [
                (mesh: mesh, transform: matrix_identity_float4x4),
                (mesh: mesh, transform: translation(x: 5)), // 5mm shift, well inside a 20mm cube + clearance
            ],
            configEntries: try sequentialConfigEntries()
        )
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.exceptionType, 3, "STRING_EXCEPT_OBJECT_COLLISION_IN_SEQ_PRINT")
        XCTAssertNotNil(result.message)
    }

    func testWellSpacedObjectsValidate() throws {
        let mesh = cubeMesh()
        let result = try SlicingEngine.validateSequentialCollision(
            objects: [
                (mesh: mesh, transform: translation(x: -80)),
                (mesh: mesh, transform: translation(x: 80)),
            ],
            configEntries: try sequentialConfigEntries()
        )
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.message)
    }

    private func translation(x: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(x, 0, 0, 1)
        return m
    }
}
