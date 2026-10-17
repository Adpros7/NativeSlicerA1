import XCTest
import simd
@testable import NativeSlicerA1

/// P7-007: `nsa1_load_gcode_toolpath` reconstructs a real toolpath from
/// an EXISTING `.gcode` file via the real `GCodeProcessor`, independent
/// of whatever object/config originally produced it.
final class GCodeLoadTests: XCTestCase {
    func testLoadsRealPreviouslySlicedGCodeFile() throws {
        // Produce a real .gcode file the normal way first, exactly like
        // a user's "Export G-code…" output.
        let loader = try BambuProfileLoader()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let gcodePath = outputDir.appendingPathComponent("plate.gcode").path

        let size: Float = 20
        let v: [Float] = [size, size, 0, size, 0, 0, 0, 0, 0, 0, size, 0, size, size, size, 0, size, size, 0, 0, size, size, 0, size]
        let i: [UInt32] = [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7, 0, 4, 7, 0, 7, 1, 1, 7, 6, 1, 6, 2, 2, 6, 5, 2, 5, 3, 4, 0, 3, 4, 3, 5]
        let mesh = LoadedMesh(vertices: v, indices: i)
        _ = try SlicingJob.slice(
            objects: [(mesh: mesh, transform: matrix_identity_float4x4)],
            loader: loader, outputPath: gcodePath
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: gcodePath))

        // Now reload it standalone, as if it were an externally-provided file.
        let configEntries = try SlicingJob.resolvedConfigEntries(loader: loader)
        let reloaded = try SlicingEngine.loadGCodeToolpath(path: gcodePath, configEntries: configEntries)

        XCTAssertFalse(reloaded.isEmpty, "reloading a real sliced file must reconstruct a non-empty toolpath")
        XCTAssertTrue(reloaded.contains { !$0.isTravel }, "must contain real extrusion moves, not just travels")
    }

    func testLoadingMissingFileThrows() {
        let missingPath = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gcode").path
        XCTAssertThrowsError(try SlicingEngine.loadGCodeToolpath(path: missingPath, configEntries: []))
    }
}
