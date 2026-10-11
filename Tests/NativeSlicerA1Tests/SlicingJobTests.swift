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
