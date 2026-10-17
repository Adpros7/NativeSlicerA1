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
    /// P4-006's connector placement state is owned by the active cut
    /// session, not baked into source mesh geometry: adding a preset at a
    /// real cut-plane point selects it, and deleting it removes only that
    /// placement. The actual mesh remains untouched until `performCut()`
    /// sends placements to the upstream cut pipeline.
    func testCutPlaneOwnsEditableConnectorPlacements() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        document.selection = document.objects[0].id
        document.cutPlaneMode = true
        document.addConnector(at: SIMD3(10, 10, 7))

        let connector = try XCTUnwrap(document.cutConnectors.first)
        XCTAssertEqual(connector.position, SIMD3(10, 10, 7))
        XCTAssertEqual(connector.preset.type, .plug)
        XCTAssertEqual(document.selectedCutConnectorID, connector.id)

        document.removeSelectedConnector()
        XCTAssertTrue(document.cutConnectors.isEmpty)
        XCTAssertNil(document.selectedCutConnectorID)
    }

    /// Editing the selected placement must update only that pending
    /// connector's real-engine preset fields; it must not create another
    /// connector or alter its plane point.
    func testEditingSelectedConnectorKeepsItsPlacement() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        document.selection = document.objects[0].id
        document.cutPlaneMode = true
        document.addConnector(at: SIMD3(3, 4, 5))
        document.updateSelectedConnector {
            $0.preset.type = .thread
            $0.preset.radius = 7
            $0.preset.height = 14
        }

        let connector = try XCTUnwrap(document.cutConnectors.first)
        XCTAssertEqual(document.cutConnectors.count, 1)
        XCTAssertEqual(connector.position, SIMD3(3, 4, 5))
        XCTAssertEqual(connector.preset.type, .thread)
        XCTAssertEqual(connector.preset.radius, 7)
        XCTAssertEqual(connector.preset.height, 14)
    }
    /// P4-007: performCut() must be undoable/redoable through the
    /// existing scene-composition UndoStack, not a parallel mechanism —
    /// undo restores the exact original object (same id, mesh intact,
    /// no leftover cut results); redo reapplies the real cut again.
    func testPerformCutIsUndoableAndRedoable() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        let originalID = try XCTUnwrap(document.objects.first?.id)
        let originalMeshID = try XCTUnwrap(document.objects.first?.sourceMeshID)
        document.selection = originalID
        document.cutPlaneMode = true
        document.setCutPlaneCenter(SIMD3(10, 10, 7))

        XCTAssertFalse(document.canUndoCut)
        document.performCut()
        XCTAssertEqual(document.objects.count, 2)
        XCTAssertTrue(document.canUndoCut)
        XCTAssertFalse(document.canRedoCut)

        document.undoCut()
        XCTAssertEqual(document.objects.count, 1)
        XCTAssertEqual(document.objects.first?.id, originalID)
        XCTAssertEqual(document.objects.first?.sourceMeshID, originalMeshID)
        XCTAssertNotNil(document.meshes[originalMeshID], "undo must restore the original mesh, not just the scene object reference")
        XCTAssertFalse(document.canUndoCut)
        XCTAssertTrue(document.canRedoCut)

        document.redoCut()
        XCTAssertEqual(document.objects.count, 2)
        XCTAssertFalse(document.objects.contains { $0.id == originalID })
        XCTAssertTrue(document.canUndoCut)
        XCTAssertFalse(document.canRedoCut)
    }

    /// P4-013: adding a default modifier sphere must center it on the
    /// real selected object's own local mesh bounding box, select it for
    /// editing, and leave the source mesh/geometry untouched — editing
    /// and deleting must affect only that one placement.
    func testModifierPlacementStateManagement() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(size: 20), into: document)
        let objectID = try XCTUnwrap(document.objects.first?.id)

        document.addModifier(to: objectID)
        let modifier = try XCTUnwrap(document.objects.first?.modifiers.first)
        XCTAssertEqual(modifier.center.x, 10, accuracy: 0.01)
        XCTAssertEqual(modifier.center.y, 10, accuracy: 0.01)
        XCTAssertEqual(modifier.center.z, 10, accuracy: 0.01)
        XCTAssertEqual(document.selectedModifierID, modifier.id)

        document.updateSelectedModifier(in: objectID) {
            $0.radius = 8
            $0.infillDensityPercent = 75
        }
        let updated = try XCTUnwrap(document.objects.first?.modifiers.first)
        XCTAssertEqual(updated.radius, 8, accuracy: 0.001)
        XCTAssertEqual(updated.configEntries.first?.value, "75%")

        document.removeSelectedModifier(from: objectID)
        XCTAssertTrue(document.objects.first?.modifiers.isEmpty ?? false)
        XCTAssertNil(document.selectedModifierID)
    }
    /// P4-007: cut lineage must survive a project save/reload, not just
    /// the raw bridge call — `ProjectDocument.save`/`load` must thread
    /// `cutGroupID` end to end.
    func testCutLineageSurvivesProjectSaveAndReload() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        document.selection = document.objects[0].id
        document.cutPlaneMode = true
        document.setCutPlaneCenter(SIMD3(10, 10, 7))
        document.performCut()
        XCTAssertEqual(document.objects.count, 2)
        let originalGroupID = try XCTUnwrap(document.objects.first?.cutGroupID)
        XCTAssertTrue(document.objects.allSatisfy { $0.cutGroupID == originalGroupID })

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appendingPathComponent("cut-pair.3mf")

        document.save(to: project)
        XCTAssertNil(document.lastError)

        let reloaded = ProjectDocument()
        reloaded.load(from: project)
        XCTAssertNil(reloaded.lastError)
        XCTAssertEqual(reloaded.objects.count, 2)
        XCTAssertTrue(reloaded.objects.allSatisfy { $0.cutGroupID == originalGroupID })
    }

    /// End-to-end P4-006: a connector placed in the active document is
    /// passed through `performCut()` into the real upstream MeshBoolean
    /// connector pipeline — result mesh volume changes because a real
    /// peg/hole pair is baked, proving it is not preview-only state.
    func testPerformCutBakesPlacedConnectorIntoResultMeshes() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        document.selection = document.objects[0].id
        document.cutPlaneMode = true
        document.setCutPlaneCenter(SIMD3(10, 10, 10))
        document.addConnector(at: SIMD3(10, 10, 10))

        document.performCut()

        XCTAssertNil(document.lastError)
        XCTAssertEqual(document.objects.count, 2)
        let resultVolume = document.objects.reduce(Float(0)) { total, object in
            total + meshVolume(try! XCTUnwrap(document.mesh(for: object)))
        }
        XCTAssertGreaterThan(resultVolume, 8001)
    }

    private func meshVolume(_ mesh: LoadedMesh) -> Float {
        var volume: Float = 0
        var i = 0
        while i < mesh.indices.count {
            func vertex(_ index: UInt32) -> SIMD3<Float> {
                let offset = Int(index) * 3
                return SIMD3(mesh.vertices[offset], mesh.vertices[offset + 1], mesh.vertices[offset + 2])
            }
            volume += simd_dot(vertex(mesh.indices[i]), simd_cross(vertex(mesh.indices[i + 1]), vertex(mesh.indices[i + 2]))) / 6
            i += 3
        }
        return abs(volume)
    }

}
