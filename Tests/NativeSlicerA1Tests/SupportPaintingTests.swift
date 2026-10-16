import XCTest
import simd
@testable import NativeSlicerA1

/// A 20mm cube sitting flush on the bed (no overhang anywhere), the same
/// proven vertex/face layout as `SlicingJobTests.cubeMesh`.
private func flushCube(size: Float = 20) -> LoadedMesh {
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

/// Proves P3-005: painting support enforcers/blockers via the real
/// engine's own `TriangleSelector` actually changes the real generated
/// G-code's support-material toolpath — not a reimplemented or fake
/// heuristic. The real print pipeline (`Print::apply`/`process`) reads
/// `ModelVolume::supported_facets` exactly as the real BambuStudio GUI's
/// painting gizmo does; these tests exercise that same real path end to
/// end via `nsa1_paint_*`/`ModelVolume::supported_facets.set()`.
///
/// Uses a cube sitting flush on the bed — zero geometric overhang
/// anywhere — as the test subject. This is the one shape confirmed (by
/// direct experimentation against the real engine) to give a genuine
/// zero support floor: unlike a floating or shelf-overhang object, it
/// triggers neither the normal overhang-angle auto-detection nor the
/// engine's independent cantilever/sharp-tail safety net, so any support
/// segments observed can only come from painted facets.
final class SupportPaintingTests: XCTestCase {
    private func supportSegmentCount(_ toolpath: [ToolpathSegment]) -> Int {
        // 14 = erSupportMaterial, 15 = erSupportMaterialInterface (raw
        // upstream `ExtrusionRole` enum — see `extrusionRole`'s doc
        // comment in SlicingEngineBridge.swift for the full mapping).
        toolpath.filter { $0.extrusionRole == 14 || $0.extrusionRole == 15 }.count
    }

    private func sliceCube(paintData: [[UInt8]] = []) throws -> [ToolpathSegment] {
        let loader = try BambuProfileLoader()
        var selection = SlicingJob.ProfileSelection()
        selection.overrides["enable_support"] = "1"
        let configEntries = try SlicingJob.resolvedConfigEntries(loader: loader, selection: selection)

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let outputPath = outputDir.appendingPathComponent("cube.gcode").path

        return try SlicingEngine.sliceToGCode(
            objects: [(mesh: flushCube(), transform: matrix_identity_float4x4)],
            configEntries: configEntries,
            outputPath: outputPath,
            paintData: paintData
        )
    }

    /// Baseline: a cube sitting flush on the bed, with `enable_support=1`
    /// and no paint, has no geometric overhang anywhere and must
    /// generate zero support.
    func testUnpaintedFlushCubeGeneratesNoSupport() throws {
        XCTAssertEqual(supportSegmentCount(try sliceCube()), 0, "a cube flush on the bed has no overhang and must generate zero support when unpainted")
    }

    /// Painting a side face as an ENFORCER must make the real engine
    /// generate real support there even though the geometry has no
    /// actual overhang — proving `ModelVolume::supported_facets` (set
    /// from the real `TriangleSelector`) genuinely drives support
    /// generation, not a reimplemented or simulated heuristic.
    func testEnforcerPaintGeneratesSupportOnFlushCube() throws {
        let mesh = flushCube()
        guard let paintState = SupportPaintState(mesh: mesh) else {
            XCTFail("nsa1_paint_create failed")
            return
        }
        // Right face (x=20) center, generous radius to cover the whole face.
        paintState.paintSphere(center: SIMD3<Float>(20, 10, 10), radius: 15, type: .enforcer)
        let serialized = paintState.serialize()
        XCTAssertFalse(serialized.isEmpty, "serialize() must produce real paint data after painting")

        let support = supportSegmentCount(try sliceCube(paintData: [serialized]))
        XCTAssertGreaterThan(support, 0, "enforcer-painted face must produce real support-material toolpath even with zero geometric overhang")
    }

    /// Painting a face as an ENFORCER then overwriting the same region
    /// with a BLOCKER must remove the support again — proving blocker
    /// painting has a real, measurable effect through the same real
    /// engine pipeline, not just that data reaches a struct field.
    func testBlockerPaintOverridesEnforcerAndRemovesSupport() throws {
        let mesh = flushCube()
        guard let paintState = SupportPaintState(mesh: mesh) else {
            XCTFail("nsa1_paint_create failed")
            return
        }
        paintState.paintSphere(center: SIMD3<Float>(20, 10, 10), radius: 15, type: .enforcer)
        paintState.paintSphere(center: SIMD3<Float>(20, 10, 10), radius: 15, type: .blocker)
        let serialized = paintState.serialize()
        XCTAssertFalse(serialized.isEmpty, "serialize() must produce real paint data after painting")

        let support = supportSegmentCount(try sliceCube(paintData: [serialized]))
        XCTAssertEqual(support, 0, "blocker-overwritten region must remove support entirely, back to the unpainted baseline")
    }

    /// P3-005: real support paint survives a native 3MF save/reload via
    /// upstream `FacetsAnnotation` serialization, then still changes the
    /// real support-generation toolpath after loading.
    func testSupportPaintPersistsThroughThreeMF() throws {
        let mesh = flushCube()
        guard let paintState = SupportPaintState(mesh: mesh) else {
            XCTFail("nsa1_paint_create failed")
            return
        }
        paintState.paintSphere(center: SIMD3<Float>(20, 10, 10), radius: 15, type: .enforcer)
        let originalData = paintState.serialize()
        XCTAssertFalse(originalData.isEmpty)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = directory.appendingPathComponent("painted.3mf")

        try SlicingEngine.storeThreeMF(
            atPath: project.path,
            objects: [(mesh: mesh, transform: matrix_identity_float4x4)],
            configEntries: [],
            paintData: [originalData]
        )
        let loadedData = SlicingEngine.loadThreeMFPaint(atPath: project.path, objectIndex: 0)
        XCTAssertFalse(loadedData.isEmpty, "3MF reload must expose saved FacetsAnnotation data")

        let support = supportSegmentCount(try sliceCube(paintData: [loadedData]))
        XCTAssertGreaterThan(support, 0, "reloaded enforcer paint must still produce real support")
    }

    /// P3-005: each viewport brush stroke is undoable/redoable without
    /// touching source mesh geometry. Undo restores a real zero-support
    /// engine result; redo restores the real enforced-support result.
    func testSupportPaintUndoRedoRestoresRealSupportOutput() throws {
        let mesh = flushCube()
        guard let paintState = SupportPaintState(mesh: mesh) else {
            XCTFail("nsa1_paint_create failed")
            return
        }
        paintState.paintSphere(center: SIMD3<Float>(20, 10, 10), radius: 15, type: .enforcer)
        XCTAssertTrue(paintState.canUndo)
        XCTAssertGreaterThan(supportSegmentCount(try sliceCube(paintData: [paintState.serialize()])), 0)

        XCTAssertTrue(paintState.undo())
        XCTAssertEqual(supportSegmentCount(try sliceCube(paintData: [paintState.serialize()])), 0)

        XCTAssertTrue(paintState.redo())
        XCTAssertGreaterThan(supportSegmentCount(try sliceCube(paintData: [paintState.serialize()])), 0)
    }
}
