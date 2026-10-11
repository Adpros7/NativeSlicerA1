import XCTest
import simd
@testable import NativeSlicerA1

private func repoRoot(from file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Tests/NativeSlicerA1Tests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

/// Proves imported geometry reaches the scene the Metal viewport reads
/// from (P1-004/P1-005 → viewport wiring), and that P1-007's 3MF project
/// persistence genuinely round-trips through the real engine's
/// `store_3mf`/`load_3mf` — not a mock or a hand-authored fixture.
@MainActor
final class ProjectDocumentTests: XCTestCase {
    private var stlURL: URL {
        repoRoot().appendingPathComponent("Sources/NativeSlicerA1/Resources/Profiles/BBL/bbl-3dp-X1.stl")
    }

    func testSTLImportAddsSceneObjectWithRealGeometry() {
        let document = ProjectDocument()
        document.importModel(at: stlURL)

        XCTAssertNil(document.lastError)
        XCTAssertEqual(document.objects.count, 1)
        let object = document.objects[0]
        XCTAssertEqual(document.mesh(for: object)?.triangleCount, 1016)
        XCTAssertEqual(document.selection, object.id)
    }

    func testMissingFileRecordsErrorInsteadOfCrashing() {
        let document = ProjectDocument()
        document.importModel(at: URL(fileURLWithPath: "/nonexistent/model.stl"))
        XCTAssertNotNil(document.lastError)
        XCTAssertTrue(document.objects.isEmpty)
    }

    func testFailedProjectLoadKeepsCurrentScene() {
        let document = ProjectDocument()
        document.importModel(at: stlURL)
        let originalID = document.objects[0].id

        document.load(from: URL(fileURLWithPath: "/nonexistent/project.3mf"))

        XCTAssertNotNil(document.lastError)
        XCTAssertEqual(document.objects.map(\.id), [originalID])
        guard let preserved = document.objects.first else { return }
        XCTAssertEqual(document.mesh(for: preserved)?.triangleCount, 1016)
    }

    func testSaveThenLoadRoundTripsGeometryAndTransformThroughRealEngine() throws {
        let document = ProjectDocument()
        document.importModel(at: stlURL)
        let objectID = try XCTUnwrap(document.objects.first?.id)
        let originalMesh = try XCTUnwrap(document.mesh(for: document.objects[0]))
        let moved = Transform.identity
            .translated(by: SIMD3(12, -5, 3))
            .rotated(by: simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)))
            .scaled(by: SIMD3(2, 2, 2))
        document.apply(moved, to: objectID)

        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nsa1-roundtrip-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        document.save(to: projectURL)
        XCTAssertNil(document.lastError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path))

        let reloaded = ProjectDocument()
        reloaded.load(from: projectURL)

        XCTAssertNil(reloaded.lastError)
        XCTAssertEqual(reloaded.objects.count, 1)
        let reloadedObject = reloaded.objects[0]
        let restoredMesh = try XCTUnwrap(reloaded.mesh(for: reloadedObject))
        XCTAssertEqual(restoredMesh.triangleCount, originalMesh.triangleCount)
        XCTAssertEqual(restoredMesh.vertices.count, originalMesh.vertices.count)
        let restoredTransform = reloadedObject.transform
        XCTAssertEqual(restoredTransform.translation.x, moved.translation.x, accuracy: 0.01)
        XCTAssertEqual(restoredTransform.translation.y, moved.translation.y, accuracy: 0.01)
        XCTAssertEqual(restoredTransform.translation.z, moved.translation.z, accuracy: 0.01)
        XCTAssertEqual(restoredTransform.scale.x, moved.scale.x, accuracy: 0.01)
        XCTAssertEqual(restoredTransform.scale.y, moved.scale.y, accuracy: 0.01)
        XCTAssertEqual(restoredTransform.scale.z, moved.scale.z, accuracy: 0.01)
        // Compare rotations by the point they map, not raw quaternion
        // components (q and -q represent the same rotation).
        let expected = moved.rotation.act(SIMD3<Float>(1, 0, 0))
        let actual = restoredTransform.rotation.act(SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.01)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.01)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.01)
    }

    /// P3-003 "settings and overrides persist across project saves and
    /// reloads", exercised at the `ProjectDocument` level (not just
    /// `SlicingJob`'s in-memory round trip): a non-default profile
    /// selection plus an override, saved to a real 3MF and reloaded into
    /// a fresh document, must come back exactly — proving the embedded
    /// config actually makes the save->reload trip through the real
    /// engine's `store_3mf`/`load_3mf`, not just through Swift state.
    func testSaveThenLoadRoundTripsProfileSelectionAndOverrides() throws {
        let document = ProjectDocument()
        document.importModel(at: stlURL)
        XCTAssertNil(document.lastError)

        document.profileSelection.machine = "Bambu Lab A1 0.6 nozzle"
        document.profileSelection.process = "0.30mm Strength @BBL A1 0.6 nozzle"
        document.profileSelection.filament = "Bambu PLA Basic @BBL A1"
        document.profileSelection.overrides["layer_height"] = "0.24"

        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nsa1-settings-roundtrip-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        document.save(to: projectURL)
        XCTAssertNil(document.lastError)

        let reloaded = ProjectDocument()
        reloaded.load(from: projectURL)

        XCTAssertNil(reloaded.lastError)
        XCTAssertEqual(reloaded.profileSelection.machine, "Bambu Lab A1 0.6 nozzle")
        XCTAssertEqual(reloaded.profileSelection.process, "0.30mm Strength @BBL A1 0.6 nozzle")
        XCTAssertEqual(reloaded.profileSelection.filament, "Bambu PLA Basic @BBL A1")
        XCTAssertEqual(reloaded.profileSelection.overrides["layer_height"], "0.24")
    }
}
