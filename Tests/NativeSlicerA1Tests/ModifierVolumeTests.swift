import XCTest
import simd
@testable import NativeSlicerA1

/// P4-013: modifier meshes (local per-volume config override). Proves the
/// real upstream `ModelVolumeType::PARAMETER_MODIFIER` + `region_config_
/// from_model_volume` (`PrintApply.cpp`) pipeline, not a reimplemented
/// spatial-lookup: a modifier volume's own config genuinely changes the
/// real sliced toolpath, with zero spatial-lookup logic written in this
/// bridge — the real engine already does it once the volume exists with
/// type PARAMETER_MODIFIER and its own config.
final class ModifierVolumeTests: XCTestCase {
    private func cubeMesh(size: Float = 20) -> LoadedMesh {
        let v: [Float] = [
            0, 0, 0, size, 0, 0, size, size, 0, 0, size, 0,
            0, 0, size, size, 0, size, size, size, size, 0, size, size,
        ]
        let i: [UInt32] = [
            0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6,
            0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2,
            2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0,
        ]
        return LoadedMesh(vertices: v, indices: i)
    }

    private func outputDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Real end-to-end proof: a 20mm cube sliced twice with the exact
    /// same LOW global `sparse_infill_density` — once plain, once with a
    /// modifier volume (same mesh/placement as the cube itself, so it
    /// covers the whole part) whose own config overrides
    /// `sparse_infill_density` to a much higher value. Only the real
    /// engine's region-config derivation can produce measurably more
    /// infill extrusion in the modifier run — this bridge wrote no
    /// infill logic at all.
    func testModifierVolumeOverridesInfillDensityInRealSlicedOutput() throws {
        let loader = try BambuProfileLoader()
        var selection = SlicingJob.ProfileSelection()
        selection.overrides["sparse_infill_density"] = "10%"
        let configEntries = try SlicingJob.resolvedConfigEntries(loader: loader, selection: selection)

        let baselineDir = try outputDir()
        defer { try? FileManager.default.removeItem(at: baselineDir) }
        let baseline = try SlicingEngine.sliceToGCode(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            configEntries: configEntries,
            outputPath: baselineDir.appendingPathComponent("baseline.gcode").path
        )

        let modifiedDir = try outputDir()
        defer { try? FileManager.default.removeItem(at: modifiedDir) }
        let modifier = ModifierVolume(
            objectIndex: 0,
            mesh: cubeMesh(),
            transform: matrix_identity_float4x4,
            configEntries: [("sparse_infill_density", "90%")]
        )
        let modified = try SlicingEngine.sliceToGCodeWithModifiers(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            modifiers: [modifier],
            configEntries: configEntries,
            outputPath: modifiedDir.appendingPathComponent("modified.gcode").path
        )

        let baselineExtrudeCount = baseline.filter { !$0.isTravel }.count
        let modifiedExtrudeCount = modified.filter { !$0.isTravel }.count
        XCTAssertGreaterThan(baselineExtrudeCount, 0)
        XCTAssertGreaterThan(
            modifiedExtrudeCount, baselineExtrudeCount + 50,
            "modifier-overridden 90% infill must produce measurably more real extrusion than the 10% baseline"
        )
    }

    /// An `objectIndex` pointing outside the real `objects` array must be
    /// ignored by the real engine construction, not crash — a user
    /// deleting an object the modifier was attached to shouldn't corrupt
    /// the whole slice.
    func testModifierWithInvalidObjectIndexIsIgnoredNotFatal() throws {
        let loader = try BambuProfileLoader()
        let configEntries = try SlicingJob.resolvedConfigEntries(loader: loader)
        let dir = try outputDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let modifier = ModifierVolume(
            objectIndex: 5, // no such object
            mesh: cubeMesh(size: 5),
            transform: matrix_identity_float4x4,
            configEntries: [("sparse_infill_density", "90%")]
        )
        let toolpath = try SlicingEngine.sliceToGCodeWithModifiers(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            modifiers: [modifier],
            configEntries: configEntries,
            outputPath: dir.appendingPathComponent("ignored.gcode").path
        )
        XCTAssertGreaterThan(toolpath.count, 0)
    }
}
