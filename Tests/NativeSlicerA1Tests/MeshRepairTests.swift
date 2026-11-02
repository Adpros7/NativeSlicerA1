import XCTest
import simd
@testable import NativeSlicerA1

/// P4-002: explicit, user-triggered, non-destructive mesh repair.
@MainActor
final class MeshRepairTests: XCTestCase {
    /// A valid cube plus one stray, fully disconnected extra triangle far
    /// outside its bounds (shares no vertices/edges with the cube) — a
    /// real defect `TriangleMesh::ReadSTLFile(repair: true)` actually
    /// fixes via `stl_remove_unconnected_facets` (all 3 of the stray
    /// triangle's edges are unconnected), not something this test
    /// fabricates expectations for.
    private func cubeWithStrayTriangle(size: Float = 20) -> LoadedMesh {
        let x = size, y = size, z = size
        var v: [Float] = [
            x, y, 0, x, 0, 0, 0, 0, 0, 0, y, 0,
            x, y, z, 0, y, z, 0, 0, z, x, 0, z,
        ]
        v.append(contentsOf: [x * 10, x * 10, x * 10, x * 11, x * 10, x * 10, x * 10, x * 11, x * 10])
        var i: [UInt32] = [
            0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7,
            0, 4, 7, 0, 7, 1, 1, 7, 6, 1, 6, 2,
            2, 6, 5, 2, 5, 3, 4, 0, 3, 4, 3, 5,
        ]
        i.append(contentsOf: [8, 9, 10])
        return LoadedMesh(vertices: v, indices: i)
    }

    private func importDirectly(_ mesh: LoadedMesh, into document: ProjectDocument) {
        let stlURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).stl")
        try? SlicingEngine.storeSTL(atPath: stlURL.path, mesh: mesh)
        document.importModel(at: stlURL)
        try? FileManager.default.removeItem(at: stlURL)
    }

    /// Direct bridge-level check: repairing a mesh with a disconnected
    /// stray facet must actually remove it (upstream's real
    /// `stl_remove_unconnected_facets`), not silently pass it through.
    func testRepairMeshChangesDefectiveGeometry() throws {
        let defective = cubeWithStrayTriangle()
        let repaired = try SlicingEngine.repairMesh(defective)
        XCTAssertEqual(defective.triangleCount, 13)
        XCTAssertEqual(repaired.triangleCount, 12, "repair must remove the disconnected stray facet")
    }

    /// Full `ProjectDocument.repairSelection()` round trip: the selected
    /// object gets a NEW id/mesh after repair, and the pre-repair mesh
    /// stays in `meshes` rather than being deleted — "new object version,
    /// original preserved" per TODO.md's P4-002 acceptance criterion.
    func testRepairSelectionPreservesOriginalMeshAndCreatesNewVersion() throws {
        let document = ProjectDocument()
        importDirectly(cubeWithStrayTriangle(), into: document)
        let originalObjectID = try XCTUnwrap(document.objects.first?.id)
        let originalMeshID = try XCTUnwrap(document.objects.first?.sourceMeshID)
        document.selection = originalObjectID

        document.repairSelection()

        XCTAssertEqual(document.objects.count, 1)
        let repairedObject = try XCTUnwrap(document.objects.first)
        XCTAssertNotEqual(repairedObject.id, originalObjectID, "repair must create a new object version")
        XCTAssertNotEqual(repairedObject.sourceMeshID, originalMeshID, "repair must create a new mesh, not mutate the original")
        XCTAssertEqual(document.selection, repairedObject.id)
        XCTAssertNotNil(document.meshes[originalMeshID], "original mesh must still be preserved, not destructively replaced")
        XCTAssertNotNil(document.meshes[repairedObject.sourceMeshID])
    }
}
