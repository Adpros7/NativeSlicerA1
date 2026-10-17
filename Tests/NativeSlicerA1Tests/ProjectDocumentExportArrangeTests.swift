import XCTest
import simd
@testable import NativeSlicerA1

/// Phase 6.5: the previously-missing "Export G-code" and "Arrange"
/// toolbar actions, now backed by `ProjectDocument.exportGCode(to:)` and
/// `arrangeActivePlate()`.
@MainActor
final class ProjectDocumentExportArrangeTests: XCTestCase {
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

    func testExportGCodeThrowsBeforeAnySlice() {
        let document = ProjectDocument()
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gcode")
        XCTAssertThrowsError(try document.exportGCode(to: dest))
    }

    func testExportGCodeCopiesRealSlicedBytesAfterSlice() async throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        document.slice()
        while document.isSlicing {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNil(document.lastError)
        XCTAssertFalse(document.toolpath.isEmpty)

        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gcode")
        defer { try? FileManager.default.removeItem(at: dest) }
        try document.exportGCode(to: dest)

        let exported = try String(contentsOf: dest, encoding: .utf8)
        XCTAssertTrue(exported.contains("G1 "), "exported file must be the real sliced G-code, not an empty/placeholder file")
    }

    func testArrangeActivePlateSeparatesOverlappingObjects() async throws {
        let document = ProjectDocument()
        importDirectly(cubeMesh(), into: document)
        importDirectly(cubeMesh(), into: document)
        // Freshly imported objects both start at the same default
        // placement — a real overlap for auto-arrange to resolve.
        XCTAssertEqual(document.objects[0].transform.translation, document.objects[1].transform.translation)

        await document.arrangeActivePlate()

        XCTAssertNil(document.lastError)
        XCTAssertNotEqual(document.objects[0].transform.translation, document.objects[1].transform.translation)
    }
}
