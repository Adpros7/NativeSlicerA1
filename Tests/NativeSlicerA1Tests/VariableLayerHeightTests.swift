import XCTest
import simd
@testable import NativeSlicerA1

/// P4-014: proves a per-object Z-range layer-height override actually
/// changes the real engine's layer height profile — verified via the real
/// toolpath Z deltas between consecutive layers, not a reimplemented
/// profile or a config-echo check.
final class VariableLayerHeightTests: XCTestCase {
    private func cubeMesh(size: Float = 20) -> LoadedMesh {
        let v: [Float] = [
            0, 0, 0, size, 0, 0, size, size, 0, 0, size, 0,
            0, 0, size, size, 0, size, size, size, size, 0, size, size,
        ]
        let i: [UInt32] = [
            0, 1, 2, 0, 2, 3,
            4, 6, 5, 4, 7, 6,
            0, 4, 5, 0, 5, 1,
            1, 5, 6, 1, 6, 2,
            2, 6, 7, 2, 7, 3,
            3, 7, 4, 3, 4, 0,
        ]
        return LoadedMesh(vertices: v, indices: i)
    }

    /// Distinct real layer Z heights present among extruding moves,
    /// derived from the actual toolpath the engine produced (not a
    /// reimplemented layer-height computation).
    private func layerZs(_ toolpath: [ToolpathSegment]) -> [Float] {
        let zs = toolpath.filter { !$0.isTravel }.map { $0.start.z }
        var sorted = Array(Set(zs.map { ($0 * 1000).rounded() / 1000 })).sorted()
        // Drop near-duplicates from floating point segment noise.
        var out: [Float] = []
        for z in sorted where out.last.map({ abs($0 - z) > 0.01 }) ?? true { out.append(z) }
        sorted = out
        return sorted
    }

    func testUniformHeightProducesConstantLayerStep() throws {
        let loader = try BambuProfileLoader()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let toolpath = try SlicingJob.slice(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            loader: loader,
            outputPath: outputDir.appendingPathComponent("uniform.gcode").path
        )
        let zs = layerZs(toolpath)
        XCTAssertGreaterThan(zs.count, 10, "expected a genuine multi-layer slice")
        let steps = zip(zs, zs.dropFirst()).map { $1 - $0 }
        let minStep = steps.min()!
        let maxStep = steps.max()!
        XCTAssertEqual(maxStep - minStep, 0, accuracy: 0.01, "uniform slice should have one consistent layer step")
    }

    /// Overrides a thick 0.3mm layer height for the object's top half
    /// (z in [10,20]) while leaving the default (thinner) height for the
    /// bottom half — the real engine's own
    /// `layer_height_profile_from_ranges` must produce visibly coarser
    /// layers (fewer, larger Z steps) only in that band.
    func testLayerHeightRangeOverridesRealToolpathStepInBandOnly() throws {
        let loader = try BambuProfileLoader()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let toolpath = try SlicingJob.slice(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            loader: loader,
            outputPath: outputDir.appendingPathComponent("ranged.gcode").path,
            layerHeightRanges: [[LayerHeightRange(zMin: 10, zMax: 20, layerHeight: 0.3)]]
        )
        let zs = layerZs(toolpath)
        XCTAssertGreaterThan(zs.count, 5)

        let lowerBandSteps = zip(zs, zs.dropFirst())
            .filter { $0.1 <= 10.01 }
            .map { $0.1 - $0.0 }
        let upperBandSteps = zip(zs, zs.dropFirst())
            .filter { $0.0 >= 9.99 && $0.1 <= 20.01 }
            .map { $0.1 - $0.0 }

        XCTAssertFalse(lowerBandSteps.isEmpty)
        XCTAssertFalse(upperBandSteps.isEmpty)

        let avgLower = lowerBandSteps.reduce(0, +) / Float(lowerBandSteps.count)
        let avgUpper = upperBandSteps.reduce(0, +) / Float(upperBandSteps.count)

        // The overridden band must use a visibly thicker real layer step
        // than the default band — proves the engine actually consumed
        // the range, not just accepted it silently.
        XCTAssertGreaterThan(avgUpper, avgLower + 0.05,
            "overridden band (avg \(avgUpper)) should be measurably thicker than default band (avg \(avgLower))")
        XCTAssertEqual(avgUpper, 0.3, accuracy: 0.05)
    }
}
