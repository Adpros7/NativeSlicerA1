import XCTest
import simd
@testable import NativeSlicerA1

/// A 20mm cube, well within the A1's 256x256mm bed — small enough to slice
/// in well under a second at 0.2mm layers, but real enough to exercise the
/// full wall/infill/top-bottom pipeline.
private func cubeMesh(size: Float = 20) -> LoadedMesh {
    let v: [Float] = [
        0, 0, 0, size, 0, 0, size, size, 0, 0, size, 0,
        0, 0, size, size, 0, size, size, size, size, 0, size, size,
    ]
    let i: [UInt32] = [
        0, 1, 2, 0, 2, 3, // bottom
        4, 6, 5, 4, 7, 6, // top
        0, 4, 5, 0, 5, 1, // front
        1, 5, 6, 1, 6, 2, // right
        2, 6, 7, 2, 7, 3, // back
        3, 7, 4, 3, 4, 0, // left
    ]
    return LoadedMesh(vertices: v, indices: i)
}

/// Proves P1-008: a real triangle mesh, placed with a real transform, goes
/// through libslic3r's own `Print::apply`/`validate`/`process`/
/// `export_gcode` pipeline (driven by the real vendored Bambu A1
/// machine/process/filament profile closure) and produces real G-code —
/// not a stub/placeholder.
final class SlicingJobTests: XCTestCase {
    func testSlicesCubeIntoRealGCode() throws {
        let loader = try BambuProfileLoader()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let outputPath = outputDir.appendingPathComponent("cube.gcode").path

        try SlicingJob.slice(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            loader: loader,
            outputPath: outputPath
        )

        let gcode = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertFalse(gcode.isEmpty)
        // Real extrusion/movement commands, not a placeholder file.
        XCTAssertTrue(gcode.contains("G1 "))
        // BambuStudio's own gcode header records the printer/profile it
        // sliced with — proves the real A1 config was used, not defaults.
        XCTAssertTrue(gcode.contains("Bambu Lab A1"), "expected A1 printer identification in generated G-code header")
        // More than a couple of header lines: a genuine multi-layer slice.
        XCTAssertGreaterThan(gcode.split(separator: "\n").count, 100)
    }

    /// P6-002: tool/color analysis must use metadata emitted by the real
    /// engine, not inferred from geometry. A real extrusion move therefore
    /// carries the upstream nonzero extrusion role through the C ABI.
    func testRealSliceCarriesEngineMoveMetadata() throws {
        let loader = try BambuProfileLoader()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let result = try SlicingEngine.sliceToGCodeWithStatistics(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            configEntries: try SlicingJob.resolvedConfigEntries(loader: loader),
            outputPath: outputDir.appendingPathComponent("metadata.gcode").path
        )
        let toolpath = result.toolpath

        XCTAssertGreaterThan(toolpath.count, 100, "statistics slicing must return the engine toolpath")
        let extrusionRoles = Set(toolpath.filter { !$0.isTravel }.map(\.extrusionRole))
        XCTAssertTrue(
            extrusionRoles.contains { $0 != 0 },
            "real extrusions must preserve GCodeProcessorResult.MoveVertex.role; got \(extrusionRoles)"
        )
    }

    /// Regression test for the `DynamicPrintConfig::full_print_config()`
    /// null-`keys_map` bug (ARCHITECTURE.md P1-008 "Upstream bug found and
    /// worked around"). Covers both affected option variants: `gcode_flavor`
    /// is a scalar `coEnum` (`PrintConfig.cpp`: `this->add("gcode_flavor",
    /// coEnum)`), set by the vendored A1 machine profile
    /// (`fdm_machine_common.json: "gcode_flavor": "marlin"`);
    /// `overhang_fan_threshold` is a per-extruder array `coEnums`
    /// (`this->add("overhang_fan_threshold", coEnums)`), set by the PLA
    /// filament profile. Both already go through every slice's
    /// enum-deserialize code path, but this test asserts specifically on
    /// the values surviving into the real G-code header's config block —
    /// proving both the `set_deserialize()` overlay and the engine's own
    /// later `serialize()` of the same options succeeded, not just "no
    /// crash". Disabling the repair pass in `CSlic3rBridge.cpp` reproduces
    /// a real SIGSEGV on this exact test (verified manually: null
    /// `ConfigOptionEnumsGenericTempl::deserialize` deref).
    func testEnumProfileOptionsSurviveRepairedKeysMap() throws {
        let loader = try BambuProfileLoader()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let outputPath = outputDir.appendingPathComponent("enum_check.gcode").path

        // Confirm the resolved A1 profile really does set these keys
        // (otherwise the assertions below would pass vacuously on the
        // engine's own built-in defaults).
        let entries = try SlicingJob.resolvedConfigEntries(loader: loader)
        XCTAssertEqual(entries.first(where: { $0.key == "gcode_flavor" })?.value, "marlin")
        XCTAssertEqual(entries.first(where: { $0.key == "overhang_fan_threshold" })?.value, "50%")

        try SlicingJob.slice(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            loader: loader,
            outputPath: outputPath
        )

        let gcode = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(gcode.contains("gcode_flavor = marlin"), "expected the A1 profile's scalar coEnum override, correctly re-serialized by the engine, in the G-code config header")
        XCTAssertTrue(gcode.contains("overhang_fan_threshold = 50%"), "expected the A1 profile's array coEnums override, correctly re-serialized by the engine, in the G-code config header")
    }

    /// Closes the P1-008/P3-003 "per-nozzle include templates not
    /// resolved" known gap (ARCHITECTURE.md): the A1-specific
    /// `machine_start_gcode` template (resolved via `BambuProfileLoader`'s
    /// `include` support) must actually reach the real engine's output,
    /// not just the resolved config dictionary.
    func testIncludedA1StartGCodeReachesRealOutput() throws {
        let loader = try BambuProfileLoader()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let outputPath = outputDir.appendingPathComponent("include_check.gcode").path

        try SlicingJob.slice(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            loader: loader,
            outputPath: outputPath
        )

        let gcode = try String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(gcode.contains("M9833.2"), "expected the A1-specific included machine_start_gcode template in the real sliced output, not the generic engine default")
    }

    /// P3-003 "selected settings actually affect generated G-code": a
    /// `layer_height` override changes the real engine's real layer
    /// count, not just a config entry that's silently dropped.
    func testLayerHeightOverrideChangesRealLayerCount() throws {
        let loader = try BambuProfileLoader()

        func totalLayers(layerHeightOverride: String?) throws -> Int {
            var selection = SlicingJob.ProfileSelection()
            if let override = layerHeightOverride {
                selection.overrides["layer_height"] = override
            }
            let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let outputPath = outputDir.appendingPathComponent("layer_height.gcode").path
            try SlicingJob.slice(objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)], loader: loader, selection: selection, outputPath: outputPath)
            let gcode = try String(contentsOfFile: outputPath, encoding: .utf8)
            guard let line = gcode.split(separator: "\n").first(where: { $0.contains("total layer number") }),
                  let countString = line.split(separator: ":").last,
                  let count = Int(countString.trimmingCharacters(in: .whitespaces))
            else {
                XCTFail("expected a '; total layer number: N' header line")
                return 0
            }
            return count
        }

        let defaultLayers = try totalLayers(layerHeightOverride: nil)
        let finerLayers = try totalLayers(layerHeightOverride: "0.08")
        XCTAssertEqual(defaultLayers, 100) // 20mm / 0.2mm default
        XCTAssertEqual(finerLayers, 249) // 20mm / 0.08mm, matching the real slicer's own layer accounting
        XCTAssertGreaterThan(finerLayers, defaultLayers)
    }

    /// P3-003 "invalid combinations are rejected safely": a process
    /// profile declared compatible only with X1-series machines
    /// (`compatible_printers`), picked against an A1 machine, must fail
    /// validation before ever reaching the engine — not silently slice
    /// with mismatched settings or crash.
    func testIncompatibleProcessProfileRejectedBeforeSlicing() throws {
        let loader = try BambuProfileLoader()
        var selection = SlicingJob.ProfileSelection()
        selection.process = "0.16mm Optimal @BBL X1C"
        let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gcode").path

        XCTAssertThrowsError(try SlicingJob.slice(objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)], loader: loader, selection: selection, outputPath: outputPath)) { error in
            XCTAssertEqual(error as? BambuProfileError, .incompatibleProfile(profile: "0.16mm Optimal @BBL X1C", machine: selection.machine))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputPath), "an invalid combination must not produce partial G-code output")
    }

    /// P3-003 "settings and overrides persist across project saves and
    /// reloads": `restoreSelection` must reconstruct the exact profile
    /// choice and override values `resolvedConfigEntries` wrote, round
    /// tripping through the real serialized config-entry string format
    /// (not a parallel in-memory-only representation).
    func testRestoreSelectionRoundTripsThroughResolvedConfigEntries() throws {
        let loader = try BambuProfileLoader()
        var selection = SlicingJob.ProfileSelection()
        selection.machine = "Bambu Lab A1 0.6 nozzle"
        selection.process = "0.30mm Strength @BBL A1 0.6 nozzle"
        selection.filament = "Bambu PLA Basic @BBL A1"
        selection.overrides = ["layer_height": "0.24", "wall_loops": "3", "enable_support": "1"]

        let entries = try SlicingJob.resolvedConfigEntries(loader: loader, selection: selection)
        let restored = SlicingJob.restoreSelection(from: entries)

        XCTAssertEqual(restored.machine, selection.machine)
        XCTAssertEqual(restored.process, selection.process)
        XCTAssertEqual(restored.filament, selection.filament)
        XCTAssertEqual(restored.overrides["layer_height"], "0.24")
        XCTAssertEqual(restored.overrides["wall_loops"], "3")
        XCTAssertEqual(restored.overrides["enable_support"], "1")
    }

    func testEmptySceneThrows() throws {
        let loader = try BambuProfileLoader()
        let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gcode").path
        XCTAssertThrowsError(try SlicingJob.slice(objects: [], loader: loader, outputPath: outputPath)) { error in
            guard case SlicingEngineError.sliceFailed = error else {
                return XCTFail("expected sliceFailed, got \(error)")
            }
        }
    }
}
