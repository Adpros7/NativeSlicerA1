import XCTest
import simd
@testable import NativeSlicerA1

/// P4-006: integration coverage for the actual consumer-facing state
/// machine a user drives through the toolbar (`cutPlaneMode` toggle,
/// `beginCutPlane`/`setCutPlaneCenter`/`setCutPlaneTilt`,
/// `performCut`) — not just the lower-level `SlicingEngine.cutModel`
/// bridge call `CutModelTests.swift` already covers directly.
@MainActor
final class ProjectDocumentCutTests: XCTestCase {
    /// Exact vertex/index layout of upstream's own `its_make_cube()` —
    /// see `CutModelTests.swift` for why a hand-rolled cube isn't used.
    private func cubeMesh(size: Float = 20) -> LoadedMesh {
        let x = size, y = size, z = size
        let v: [Float] = [
            x, y, 0, x, 0, 0, 0, 0, 0, 0, y, 0,
            x, y, z, 0, y, z, 0, 0, z, x, 0, z,
        ]
        let i: [UInt32] = [
            0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7,
            0, 4, 7, 0, 7, 1, 1, 7, 6, 1, 6, 2,
            2, 6, 5, 2, 5, 3, 4, 0, 3, 4, 3, 5,
        ]
        return LoadedMesh(vertices: v, indices: i)
    }

    /// Imports `mesh` into `document` the same way an STL import would
    /// (new mesh id + scene object), bypassing the file-system round
    /// trip so this test stays fast and self-contained.
    private func importDirectly(_ mesh: LoadedMesh, into document: ProjectDocument, at transform: Transform = .identity) {
        let stlURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).stl")
        try? SlicingEngine.storeSTL(atPath: stlURL.path, mesh: mesh)
        document.importModel(at: stlURL)
        try? FileManager.default.removeItem(at: stlURL)
    }

    func testTogglingCutPlaneModeInitializesAPlaneOnSelection() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        XCTAssertEqual(document.objects.count, 1)
        document.selection = document.objects[0].id

        XCTAssertNil(document.cutPlane)
        document.cutPlaneMode = true
        let plane = try XCTUnwrap(document.cutPlane)
        // Auto-centered on the (20mm cube's) world bounding box center.
        XCTAssertEqual(plane.center.x, 10, accuracy: 0.5)
        XCTAssertEqual(plane.center.y, 10, accuracy: 0.5)
        XCTAssertEqual(plane.center.z, 10, accuracy: 0.5)

        document.cutPlaneMode = false
        XCTAssertNil(document.cutPlane)
    }

    /// Full round trip through the real state machine: toggle cut mode,
    /// reposition the plane, perform the real cut, and verify the scene
    /// was actually replaced with 2 real new objects (not the original).
    func testPerformCutReplacesSelectedObjectWithRealResults() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        let originalID = try XCTUnwrap(document.objects.first?.id)
        document.selection = originalID
        document.cutPlaneMode = true
        document.setCutPlaneCenter(SIMD3(10, 10, 7))
        document.cutKeepMode = .both

        document.performCut()

        XCTAssertNil(document.lastError)
        XCTAssertEqual(document.objects.count, 2)
        XCTAssertFalse(document.objects.contains { $0.id == originalID }, "original object must be consumed by the cut")
        // cutPlaneMode auto-exits and clears the plane after a successful cut.
        XCTAssertFalse(document.cutPlaneMode)
        XCTAssertNil(document.cutPlane)
        // Each real result mesh must actually exist in the mesh table.
        for object in document.objects {
            XCTAssertNotNil(document.meshes[object.sourceMeshID])
        }
        // A new selection must point at one of the real results.
        XCTAssertTrue(document.objects.contains { $0.id == document.selection })
    }

    /// `cutKeepMode: .lowerOnly` must leave exactly 1 real result.
    func testPerformCutRespectsKeepMode() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        document.selection = document.objects[0].id
        document.cutPlaneMode = true
        document.setCutPlaneCenter(SIMD3(10, 10, 7))
        document.cutKeepMode = .lowerOnly

        document.performCut()

        XCTAssertNil(document.lastError)
        XCTAssertEqual(document.objects.count, 1)
    }
}
