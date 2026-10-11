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

    func testPressureAdvanceCalibrationSlicesBundledPatternThroughRealEngine() throws {
        let loader = try BambuProfileLoader()
        let request = CalibrationRequest(
            workflow: .pressureAdvance,
            start: 0,
            end: 0.004,
            step: 0.002,
            selection: .init()
        )
        try CalibrationJob.validate(request, loader: loader, capabilities: .all)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gcode")
        defer {
            if FileManager.default.fileExists(atPath: output.path) {
                try? FileManager.default.removeItem(at: output)
            }
        }

        let generation = try SlicingEngine.generateCalibrationGCode(
            request: request,
            resourceURL: try XCTUnwrap(CalibrationResources.url(named: "pressure_advance_test")),
            configEntries: try SlicingJob.resolvedConfigEntries(loader: loader),
            outputPath: output.path
        )

        XCTAssertFalse(generation.toolpath.isEmpty)
        XCTAssertEqual(generation.blocks.map(\.value), [0, 0.002, 0.004])
        let gcode = try String(contentsOf: output)
        let markers = ["M900 K0", "M900 K0.002", "M900 K0.004"]
        var searchStart = gcode.startIndex
        for marker in markers {
            let range = try XCTUnwrap(gcode.range(of: marker, range: searchStart..<gcode.endIndex))
            searchStart = range.upperBound
        }
    }
    
    func testTemperatureCalibrationSlicesTowerThroughRealEngine() throws {
        let loader = try BambuProfileLoader()
        let request = CalibrationRequest(
            workflow: .temperature,
            start: 230,
            end: 220,
            step: 5,
            selection: .init()
        )
        try CalibrationJob.validate(request, loader: loader, capabilities: .all)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gcode")
        defer { try? FileManager.default.removeItem(at: output) }

        let generation = try SlicingEngine.generateCalibrationGCode(
            request: request,
            resourceURL: try XCTUnwrap(CalibrationResources.url(named: "temperature_tower")),
            configEntries: try SlicingJob.resolvedConfigEntries(loader: loader),
            outputPath: output.path
        )

        XCTAssertFalse(generation.toolpath.isEmpty)
        XCTAssertEqual(generation.blocks.map(\.value), [230, 225, 220])
        let gcode = try String(contentsOf: output)
        var currentZ = -1.0
        var temperatureChanges: [(temperature: Int, z: Double)] = []
        for line in gcode.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.hasPrefix("; Z_HEIGHT: ") {
                currentZ = Double(text.dropFirst("; Z_HEIGHT: ".count)) ?? currentZ
            } else if text.hasPrefix("M104 S"), text.contains("; set nozzle temperature"),
                      let temperature = Int(text.dropFirst("M104 S".count).split(separator: " ").first ?? "") {
                temperatureChanges.append((temperature, currentZ))
            }
        }
        for (temperature, expectedZ) in [(230, 0.2), (225, 10.2), (220, 20.2)] {
            let change = try XCTUnwrap(
                temperatureChanges.first(where: { $0.temperature == temperature }),
                "missing layer temperature \(temperature)"
            )
            XCTAssertEqual(change.z, expectedZ, accuracy: 0.2)
        }
        var searchStart = gcode.startIndex
        for temperature in [230, 225, 220] {
            let marker = "M104 S\(temperature)"
            let range = try XCTUnwrap(
                gcode.range(of: marker, range: searchStart..<gcode.endIndex),
                "missing \(marker)"
            )
            searchStart = range.upperBound
        }
    }
    func testRetractionCalibrationUsesRealEngineRetractionBlocksAndToolpath() throws {
        let loader = try BambuProfileLoader()
        let request = CalibrationRequest(
            workflow: .retraction,
            start: 0.2,
            end: 0.6,
            step: 0.2,
            selection: .init()
        )
        try CalibrationJob.validate(request, loader: loader, capabilities: .all)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gcode")
        defer { try? FileManager.default.removeItem(at: output) }

        let generation = try SlicingEngine.generateCalibrationGCode(
            request: request,
            resourceURL: try XCTUnwrap(CalibrationResources.url(named: "retraction_tower")),
            configEntries: try SlicingJob.resolvedConfigEntries(loader: loader),
            outputPath: output.path
        )

        XCTAssertFalse(generation.toolpath.isEmpty)
        XCTAssertEqual(generation.blocks.count, 3)
        XCTAssertTrue(zip(generation.blocks.map(\.value), [0.2, 0.4, 0.6]).allSatisfy { abs($0.0 - $0.1) < 0.0001 })
        XCTAssertGreaterThan(generation.toolpath.filter(\.isTravel).count, 0)
        let gcode = try String(contentsOf: output)
        XCTAssertGreaterThanOrEqual(gcode.components(separatedBy: "Calib_Retraction_tower:").count, 4)
    }

    func testMaxVolumetricSpeedCalibrationSlicesSTEPThroughRealEngine() throws {
        let loader = try BambuProfileLoader()
        let request = CalibrationRequest(
            workflow: .maxVolumetricSpeed,
            start: 5,
            end: 7,
            step: 1,
            selection: .init()
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gcode")

        let generation = try SlicingEngine.generateCalibrationGCode(
            request: request,
            resourceURL: try XCTUnwrap(CalibrationResources.url(named: "SpeedTestStructure")),
            configEntries: try SlicingJob.resolvedConfigEntries(loader: loader),
            outputPath: output.path
        )

        XCTAssertFalse(generation.toolpath.isEmpty)
        XCTAssertEqual(generation.blocks.map(\.value), [5, 6, 7])
        XCTAssertFalse(try String(contentsOf: output).isEmpty)
    }

    /// P3-002: proves the generated G-code's outer-wall feed rate actually
    /// implements the requested mm3/s values — not just that calibration
    /// metadata (`blocks`) echoes them back. Parses the real per-layer
    /// speed the engine wrote (the same `Calib_Vol_speed_Tower` ramp
    /// upstream's `GCode.cpp` computes: `outer_wall_speed =
    /// round(params.start + print_z * params.step)` in mm/s, converted to
    /// F in mm/min) and compares it against the expected speed derived
    /// independently from the real `Flow::mm3_per_mm()` formula
    /// (`height * (width - height * (1 - pi/4))`, `Flow.cpp:213-224`) for
    /// the exact line width/layer height this workflow applies
    /// (`nozzle_diameter * 1.75` / `nozzle_diameter * 0.8`,
    /// `Plater.cpp:21420-21421`): `speed_mm_s = (requestedMm3PerS +
    /// z * requestedStepMm3PerS) / mm3PerMm`.
    func testMaxVolumetricSpeedCalibrationGCodeMatchesRequestedFlowRate() throws {
        let loader = try BambuProfileLoader()
        let request = CalibrationRequest(
            workflow: .maxVolumetricSpeed,
            start: 5,
            end: 7,
            step: 1,
            selection: .init()
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gcode")
        defer { try? FileManager.default.removeItem(at: output) }

        _ = try SlicingEngine.generateCalibrationGCode(
            request: request,
            resourceURL: try XCTUnwrap(CalibrationResources.url(named: "SpeedTestStructure")),
            configEntries: try SlicingJob.resolvedConfigEntries(loader: loader),
            outputPath: output.path
        )
        let gcode = try String(contentsOf: output)

        // Same nozzle-derived constants nsa1_generate_calibration_gcode
        // applies for this workflow (CSlic3rBridge.cpp), including the
        // default A1 profile's filament_flow_ratio (Generic PLA @base.json
        // = 0.98) the engine's own flow math multiplies in.
        let nozzleDiameter = 0.4
        let lineWidth = nozzleDiameter * 1.75
        let layerHeight = nozzleDiameter * 0.8
        let filamentFlowRatio = 0.98
        let mm3PerMm = layerHeight * (lineWidth - layerHeight * (1 - .pi / 4)) * filamentFlowRatio

        // Independently confirm the overridden line width/layer height
        // actually reached the sliced output (not just the arithmetic
        // above) — real per-layer Z spacing and the real "; LINE_WIDTH:"
        // comment BambuStudio's own G-code writer emits for the perimeter.
        XCTAssertTrue(gcode.contains("; LINE_WIDTH: 0.7"), "expected the overridden outer_wall_line_width (0.7mm) to reach the sliced output")
        let zHeights = gcode.split(separator: "\n")
            .filter { $0.hasPrefix("; Z_HEIGHT:") }
            .compactMap { Double($0.dropFirst("; Z_HEIGHT:".count).trimmingCharacters(in: .whitespaces)) }
            .reduce(into: [Double]()) { if $0.last != $1 { $0.append($1) } } // spiral vase repeats the final marker
        for (previous, next) in zip(zHeights, zHeights.dropFirst()) {
            XCTAssertEqual(next - previous, layerHeight, accuracy: 0.001, "expected the overridden layer_height (0.32mm) to reach the sliced output")
        }

        // Walk "; Z_HEIGHT: <z>" markers; within each layer, the first bare
        // "G1 F<value>" line (no X/Y/E) after the prime retraction is the
        // real engine's calibrated outer-wall speed for that layer. The
        // writer omits a redundant F command when the rounded speed hasn't
        // changed since the previous layer, so not every layer has one;
        // spiral vase also repeats the final Z marker once at EOF, which a
        // same-value marker must not reopen as a new block.
        var observed: [(z: Double, feedPerMin: Double)] = []
        var currentZ: Double?
        var sawFeedForCurrentZ = false
        for rawLine in gcode.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("; Z_HEIGHT:") {
                let z = Double(line.dropFirst("; Z_HEIGHT:".count).trimmingCharacters(in: .whitespaces))
                if z != currentZ {
                    currentZ = z
                    sawFeedForCurrentZ = false
                }
                continue
            }
            guard let z = currentZ, !sawFeedForCurrentZ,
                  line.hasPrefix("G1 F"), Double(line.dropFirst("G1 F".count)) != nil
            else { continue }
            observed.append((z, Double(line.dropFirst("G1 F".count))!))
            sawFeedForCurrentZ = true
        }

        // Exclude the first layer (brim, not the calibrated tower wall),
        // which never runs at the calibrated outer-wall speed.
        let rampLayers = observed.count > 1 ? Array(observed.dropFirst()) : []
        XCTAssertGreaterThanOrEqual(rampLayers.count, 5, "expected most of the 9-layer tower to report an explicit calibrated speed")

        for (z, feedPerMin) in rampLayers {
            let expectedSpeedMmPerS = (request.start + z * request.step) / mm3PerMm
            let expectedFeedPerMin = (expectedSpeedMmPerS).rounded() * 60
            XCTAssertEqual(
                feedPerMin, expectedFeedPerMin, accuracy: 1,
                "at Z=\(z), expected the real Calib_Vol_speed_Tower ramp (requested \(request.start)-\(request.end) mm3/s) to set F\(expectedFeedPerMin), got F\(feedPerMin)"
            )
        }

        // The ramp must actually move, proving the per-layer ConfigOption
        // override reaches `Print::process()` rather than staying static.
        if let first = rampLayers.first, let last = rampLayers.last {
            XCTAssertGreaterThan(last.feedPerMin, first.feedPerMin)
        }
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
