import XCTest
@testable import NativeSlicerA1

private func repoRoot(from file: StaticString = #filePath) -> URL {
    URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent() // Tests/NativeSlicerA1Tests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
}

@MainActor
final class CalibrationJobTests: XCTestCase {
    func testBundledCalibrationResourcesExist() throws {
        for name in [
            "flowrate-test-pass1",
            "flowrate-test-pass2",
            "temperature_tower",
            "retraction_tower",
            "SpeedTestStructure",
        ] {
            XCTAssertNotNil(CalibrationResources.url(named: name), "missing bundled calibration resource \(name)")
        }
    }

    func testFlowRateRejectsNonPositiveStep() throws {
        let request = CalibrationRequest(
            workflow: .flowRate,
            start: 0.95,
            end: 1.05,
            step: 0,
            selection: .init()
        )

        XCTAssertThrowsError(try CalibrationJob.validate(
            request,
            loader: try BambuProfileLoader(),
            capabilities: .all
        )) { error in
            XCTAssertEqual(
                error as? CalibrationError,
                .invalidRange(start: 0.95, end: 1.05, step: 0)
            )
        }
    }

    func testPressureAdvanceRequiresExplicitCapability() throws {
        let request = CalibrationRequest(
            workflow: .pressureAdvance,
            start: 0,
            end: 0.02,
            step: 0.002,
            selection: .init()
        )

        XCTAssertThrowsError(try CalibrationJob.validate(
            request,
            loader: try BambuProfileLoader(),
            capabilities: []
        )) { error in
            XCTAssertEqual(
                error as? CalibrationError,
                .unsupportedCapability(.pressureAdvance)
            )
        }
    }

    func testCalibrationValidatesProfileBeforeCapability() throws {
        var selection = SlicingJob.ProfileSelection()
        selection.process = "missing profile"
        let request = CalibrationRequest(
            workflow: .temperature,
            start: 230,
            end: 220,
            step: 5,
            selection: selection
        )

        XCTAssertThrowsError(try CalibrationJob.validate(
            request,
            loader: try BambuProfileLoader(),
            capabilities: []
        )) { error in
            XCTAssertTrue(error is BambuProfileError)
        }
    }

    func testMissingCalibrationResourceThrowsBridgeError() throws {
        let loader = try BambuProfileLoader()
        let request = CalibrationRequest(
            workflow: .flowRate,
            start: 0.8,
            end: 1.2,
            step: 0.05,
            selection: .init()
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gcode")

        XCTAssertThrowsError(try SlicingEngine.generateCalibrationGCode(
            request: request,
            resourceURL: URL(fileURLWithPath: "/missing/calibration.stl"),
            configEntries: try SlicingJob.resolvedConfigEntries(loader: loader),
            outputPath: output.path
        )) { error in
            guard case let SlicingEngineError.sliceFailed(message) = error else {
                return XCTFail("expected sliceFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("missing calibration resource"))
        }
    }

    func testFlowRateCalibrationSlicesBundledPassOneThroughRealEngine() throws {
        let loader = try BambuProfileLoader()
        let request = CalibrationRequest(
            workflow: .flowRate,
            start: 0.8,
            end: 1.2,
            step: 0.05,
            selection: .init()
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gcode")
        defer { try? FileManager.default.removeItem(at: output) }

        let generation = try SlicingEngine.generateCalibrationGCode(
            request: request,
            resourceURL: try XCTUnwrap(CalibrationResources.url(named: "flowrate-test-pass1")),
            configEntries: try SlicingJob.resolvedConfigEntries(loader: loader),
            outputPath: output.path
        )

        XCTAssertFalse(generation.toolpath.isEmpty)
        XCTAssertEqual(generation.blocks.map(\.value), [0.8, 0.85, 0.9, 0.95, 1, 1.05, 1.1, 1.15, 1.2])
        XCTAssertTrue(try String(contentsOf: output).contains("Bambu Lab A1"))
    }
    /// Verify ProjectDocument creation + importModel works in this test class.
    func testProjectDocumentImportInCalibrationContext() {
        let document = ProjectDocument()
        document.importModel(at: repoRoot().appendingPathComponent("Sources/NativeSlicerA1/Resources/Profiles/BBL/bbl-3dp-X1.stl"))
        XCTAssertNil(document.lastError)
        XCTAssertEqual(document.objects.count, 1)
    }

    /// P3-003/Calibration: document-level calibration populates toolpath
    /// and lastCalibration through the real engine — exercises
    /// `ProjectDocument.calibrate()` end-to-end.
    func testDocumentCalibrationPopulatesToolpathAndBlocks() async throws {
        let document = ProjectDocument()
        await document.calibrate()

        // Calibration must produce nonempty toolpath and blocks.
        XCTAssertFalse(document.toolpath.isEmpty)
        let blocks = document.lastCalibration?.blocks ?? []
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertEqual(blocks.map(\.value), [0.8, 0.85, 0.9, 0.95, 1, 1.05, 1.1, 1.15, 1.2])
        // No error from successful calibration.
        XCTAssertNil(document.lastError)
    }

    /// P3-003/Calibration: calibrate() preserves existing scene object IDs
    /// and yields nonempty toolpath + blocks — verifies calibration
    /// replaces toolpath, not scene.
    func testDocumentCalibrationPreservesObjectIDsAndGeneratesToolpath() async throws {
        let document = ProjectDocument()
        document.importModel(at: repoRoot().appendingPathComponent("Sources/NativeSlicerA1/Resources/Profiles/BBL/bbl-3dp-X1.stl"))
        XCTAssertNil(document.lastError)
        XCTAssertEqual(document.objects.count, 1)
        let originalIDs = document.objects.map(\.id)

        await document.calibrate()

        // Object IDs must be unchanged (calibration replaces toolpath, not scene).
        XCTAssertEqual(document.objects.map(\.id), originalIDs)
        // Existing meshes are untouched.
        XCTAssertEqual(document.mesh(for: document.objects[0])?.triangleCount, 1016)
        // Calibration must produce nonempty toolpath and blocks.
        XCTAssertFalse(document.toolpath.isEmpty)
        let blocks = document.lastCalibration?.blocks ?? []
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertEqual(blocks.map(\.value), [0.8, 0.85, 0.9, 0.95, 1, 1.05, 1.1, 1.15, 1.2])
        // No error from successful calibration.
        XCTAssertNil(document.lastError)
    }
}
