import XCTest
import simd
@testable import NativeSlicerA1

/// P4-009: assembly/plate previews. Upstream's `GUI/Plater.cpp` renders a
/// full 3D thumbnail per plate; this app computes the real per-object
/// world-space XY footprint (via the same `worldBoundingBox` P4-006's cut
/// plane already uses) projected into bed-relative coordinates, which is
/// what a 2D preview/thumbnail needs and what a real "does this fit on
/// the bed" check needs — not a placeholder visual.
@MainActor
final class PlatePreviewTests: XCTestCase {
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

    /// A real object's real world-space bounding box must map correctly
    /// into bed-relative XY coordinates (bed origin at the corner,
    /// matching the A1's real coordinate convention), and objects that
    /// fit the 256x256 bed must be flagged as within bounds.
    func testPlatePreviewReportsRealBedRelativeFootprint() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(size: 20), into: document)
        document.apply(Transform(translation: SIMD3(50, 60, 0), rotation: .init(ix: 0, iy: 0, iz: 0, r: 1), scale: SIMD3(1, 1, 1)), to: document.objects[0].id)

        let preview = document.platePreview(bedWidth: 256, bedHeight: 256)
        XCTAssertEqual(preview.count, 1)
        let entry = try XCTUnwrap(preview.first)
        XCTAssertEqual(entry.minX, 50, accuracy: 0.01)
        XCTAssertEqual(entry.minY, 60, accuracy: 0.01)
        XCTAssertEqual(entry.maxX, 70, accuracy: 0.01)
        XCTAssertEqual(entry.maxY, 80, accuracy: 0.01)
        XCTAssertTrue(entry.withinBed)
    }

    /// An object placed (partly) outside the bed must be flagged, not
    /// silently reported as fitting.
    func testPlatePreviewFlagsObjectsOutsideBedBounds() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(size: 20), into: document)
        document.apply(Transform(translation: SIMD3(250, 0, 0), rotation: .init(ix: 0, iy: 0, iz: 0, r: 1), scale: SIMD3(1, 1, 1)), to: document.objects[0].id)

        let preview = document.platePreview(bedWidth: 256, bedHeight: 256)
        XCTAssertEqual(preview.count, 1)
        XCTAssertFalse(try XCTUnwrap(preview.first).withinBed)
    }

    /// Only the active plate's objects appear in the preview — a second
    /// plate's objects must not leak in.
    func testPlatePreviewOnlyIncludesActivePlateObjects() throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        let secondPlateID = document.addPlate()
        document.activePlateID = secondPlateID
        importDirectly(cubeMesh(size: 10), into: document)

        let preview = document.platePreview(bedWidth: 256, bedHeight: 256)
        XCTAssertEqual(preview.count, 1)
        XCTAssertEqual(preview.first?.objectID, document.objectsOnActivePlate.first?.id)
    }
}
