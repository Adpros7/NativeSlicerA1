import XCTest
import simd
@testable import NativeSlicerA1

/// P4-008: multi-plate arrangement. The A1 itself is single-bed hardware
/// (FEATURE_PARITY.md §3/§5/§7) — the real value here is batch jobs and
/// per-plate settings: group placed objects into independent plates,
/// each with its own real `SlicingEngine.cutModel`/`autoArrange`/`slice`
/// operating only on that plate's objects, sliced/exported one at a time.
@MainActor
final class MultiPlateTests: XCTestCase {
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

    private func importDirectly(_ mesh: LoadedMesh, into document: ProjectDocument) {
        let stlURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).stl")
        try? SlicingEngine.storeSTL(atPath: stlURL.path, mesh: mesh)
        document.importModel(at: stlURL)
        try? FileManager.default.removeItem(at: stlURL)
    }

    /// A fresh project starts with exactly one default plate, and every
    /// newly imported object is assigned to the currently active plate.
    func testNewProjectStartsWithOneDefaultPlateAndAssignsImportsToIt() throws {
        let document = ProjectDocument()
        XCTAssertEqual(document.plates.count, 1)
        let defaultPlateID = try XCTUnwrap(document.plates.first?.id)
        XCTAssertEqual(document.activePlateID, defaultPlateID)

        importDirectly(cubeMesh(), into: document)
        XCTAssertEqual(document.objects.first?.plateID, defaultPlateID)
    }

    /// Adding a plate and switching to it must route subsequent imports
    /// to the NEW plate, leaving the first plate's objects untouched.
    func testAddingAndSwitchingPlatesRoutesNewImportsCorrectly() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        let firstPlateID = document.activePlateID
        XCTAssertEqual(document.objectsOnActivePlate.count, 1)

        let secondPlateID = document.addPlate()
        XCTAssertEqual(document.plates.count, 2)
        document.activePlateID = secondPlateID
        importDirectly(cubeMesh(size: 10), into: document)

        XCTAssertEqual(document.objects.count, 2)
        let onFirst = document.objects.filter { $0.plateID == firstPlateID }
        let onSecond = document.objects.filter { $0.plateID == secondPlateID }
        XCTAssertEqual(onFirst.count, 1)
        XCTAssertEqual(onSecond.count, 1)
        XCTAssertEqual(document.objectsOnActivePlate.count, 1)
        XCTAssertEqual(document.objectsOnActivePlate.first?.plateID, secondPlateID)
    }

    /// Removing a plate must reassign its objects to the remaining
    /// (now-active) plate rather than silently deleting real geometry —
    /// batch workflows must never lose placed objects.
    func testRemovingAPlateReassignsItsObjectsRatherThanDeletingThem() throws {
        let document = ProjectDocument()
        let firstPlateID = document.activePlateID
        importDirectly(cubeMesh(), into: document)
        let secondPlateID = document.addPlate()
        document.activePlateID = secondPlateID
        importDirectly(cubeMesh(size: 10), into: document)
        XCTAssertEqual(document.objects.count, 2)

        document.removePlate(secondPlateID)

        XCTAssertEqual(document.plates.count, 1)
        XCTAssertEqual(document.objects.count, 2, "objects must survive plate removal")
        XCTAssertTrue(document.objects.allSatisfy { $0.plateID == firstPlateID })
        XCTAssertEqual(document.activePlateID, firstPlateID)
    }

    /// The real auto-arrange bridge (P4-011) must only pack objects on
    /// the active plate — a second plate's objects must be untouched and
    /// must not be used as obstacles.
    func testAutoArrangeActivePlateOnlyMovesThatPlatesObjects() async throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        let firstPlateID = document.activePlateID
        let originalTransform = document.objects[0].transform.matrix

        let secondPlateID = document.addPlate()
        document.activePlateID = secondPlateID
        importDirectly(cubeMesh(size: 10), into: document)
        importDirectly(cubeMesh(size: 10), into: document)

        try await document.autoArrangeActivePlate(bedWidth: 256, bedHeight: 256, clearance: 2)

        XCTAssertEqual(document.objects.first { $0.plateID == firstPlateID }?.transform.matrix, originalTransform, "other plate's object must be untouched")
        let secondPlateObjects = document.objects.filter { $0.plateID == secondPlateID }
        XCTAssertEqual(secondPlateObjects.count, 2)
    }

    /// Plate assignment must survive a real project save/reload.
    func testPlateAssignmentSurvivesProjectSaveAndReload() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        let secondPlateID = document.addPlate()
        document.activePlateID = secondPlateID
        importDirectly(cubeMesh(size: 10), into: document)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appendingPathComponent("multi-plate.3mf")

        document.save(to: project)
        XCTAssertNil(document.lastError)

        let reloaded = ProjectDocument()
        reloaded.load(from: project)
        XCTAssertNil(reloaded.lastError)
        XCTAssertEqual(reloaded.plates.count, 2)
        XCTAssertEqual(reloaded.objects.count, 2)
        XCTAssertEqual(Set(reloaded.objects.map { $0.plateID }).count, 2, "two objects must still be on two distinct plates")
    }
}
