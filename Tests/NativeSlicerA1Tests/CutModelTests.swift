import XCTest
import simd
@testable import NativeSlicerA1

/// P4-004/P4-006 prerequisite: this bridge had ZERO test coverage before
/// this file despite being marked complete in TODO.md. Building this
/// coverage found and fixed two real bugs:
///
/// 1. `scene_object_from_model_object` returned `matrix16: nullptr` for
///    every cut result, silently dropping the real engine's own post-cut
///    instance placement (`ModelObject::cut`'s `reset_instance_transformation`)
///    — AND separately used `obj.mesh()` (which already bakes in the full
///    instance transform) while *also* trying to return that same
///    instance transform, double-applying it. Fixed: `scene_object_from_model_object`
///    now uses `obj.raw_mesh()` (volume transform only) and returns the
///    real instance transform via `matrix16`, applied exactly once by
///    the caller.
/// 2. `scene_object_from_model_object` called `nsa1_free_mesh(mesh_data)`
///    after handing `mesh_data`'s `vertices`/`indices` arrays to the
///    returned `NSA1SceneObject` — `nsa1_free_mesh` deletes those same
///    arrays, so the returned scene object held dangling pointers (a
///    real double-free, reproduced as a `malloc: *** error for object …
///    pointer being freed was not allocated` abort the first time this
///    path was actually exercised). Fixed: delete only the `NSA1Mesh`
///    wrapper struct, not the arrays it handed off.
///
/// Also discovered real (intentional, documented) upstream behavior: cut
/// results do NOT preserve their exact pre-cut world XY position —
/// `ModelObject::cut`'s `reset_instance_transformation` recenters each
/// piece around its own geometry (`invalidate_translations` ->
/// `center_around_origin`) without always compensating the instance
/// offset for that recentering. This matches the code's own comment on
/// `local_displace` ("so at least a part of the upper part will always
/// be visible and draggable") — real slicers expect users to reposition
/// cut pieces afterward. Tests below therefore verify translation-
/// independent invariants (size, volume, mutual adjacency) rather than
/// an exact absolute position, which is not what the real engine does.
final class CutModelTests: XCTestCase {
    /// Exact vertex/index layout of upstream's own `its_make_cube()`
    /// (`TriangleMesh.cpp`) — verified via direct experimentation that a
    /// hand-rolled cube with a different diagonal-split convention can
    /// trigger a real `cut_mesh` capping robustness edge case (produces
    /// an uncapped hole instead of a closed cross-section); the exact
    /// upstream primitive does not.
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

    /// World-space bounding box of `mesh` placed by `transform`.
    private func worldBoundingBox(_ mesh: LoadedMesh, _ transform: simd_float4x4) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var i = 0
        while i < mesh.vertices.count {
            let local = SIMD4<Float>(mesh.vertices[i], mesh.vertices[i + 1], mesh.vertices[i + 2], 1)
            let world4 = transform * local
            let world = SIMD3(world4.x, world4.y, world4.z) / world4.w
            lo = SIMD3(x: Swift.min(lo.x, world.x), y: Swift.min(lo.y, world.y), z: Swift.min(lo.z, world.z))
            hi = SIMD3(x: Swift.max(hi.x, world.x), y: Swift.max(hi.y, world.y), z: Swift.max(hi.z, world.z))
            i += 3
        }
        return (lo, hi)
    }

    /// Signed-tetrahedron volume of a watertight mesh (standard divergence-
    /// theorem formula) — proves the cut didn't lose/duplicate geometry,
    /// not a reimplementation of the cut itself.
    private func meshVolume(_ mesh: LoadedMesh) -> Float {
        var volume: Float = 0
        var i = 0
        while i < mesh.indices.count {
            func vertex(_ idx: UInt32) -> SIMD3<Float> {
                let base = Int(idx) * 3
                return SIMD3(mesh.vertices[base], mesh.vertices[base + 1], mesh.vertices[base + 2])
            }
            let a = vertex(mesh.indices[i])
            let b = vertex(mesh.indices[i + 1])
            let c = vertex(mesh.indices[i + 2])
            volume += simd_dot(a, simd_cross(b, c)) / 6
            i += 3
        }
        return abs(volume)
    }

    private func horizontalPlane(atZ z: Float, extent: Float = 100) -> [(Float, Float, Float)] {
        [
            (-extent, -extent, z),
            (extent, -extent, z),
            (extent, extent, z),
            (-extent, extent, z),
        ]
    }

    private func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t.x, t.y, t.z, 1)
        return m
    }

    /// `cutMode: .lowerOnly`/`.upperOnly` must return exactly 1 real
    /// result each; `.both` must return 2 — the real engine's own
    /// `ModelObjectCutAttribute` dispatch, not a client-side filter.
    func testCutModeControlsWhichHalvesAreReturned() throws {
        let both = try SlicingEngine.cutModel(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            planePoints: horizontalPlane(atZ: 10), cutMode: .both)
        let lowerOnly = try SlicingEngine.cutModel(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            planePoints: horizontalPlane(atZ: 10), cutMode: .lowerOnly)
        let upperOnly = try SlicingEngine.cutModel(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            planePoints: horizontalPlane(atZ: 10), cutMode: .upperOnly)

        XCTAssertEqual(both.count, 2)
        XCTAssertEqual(lowerOnly.count, 1)
        XCTAssertEqual(upperOnly.count, 1)
    }

    /// The two real halves must sum to exactly the original cube's volume
    /// (8000 mm^3) — the real engine neither loses nor duplicates
    /// geometry across the cut, including the new cap faces it adds at
    /// the cut plane. Also the ROOT CAUSE REGRESSION TEST for the
    /// double-free bug: before the fix, this crashed with
    /// `malloc: *** error for object … pointer being freed was not
    /// allocated` the moment `nsa1_free_cut_results` tried to free the
    /// dangling vertex/index arrays.
    func testCutHalvesVolumeSumsToOriginal() throws {
        let originalVolume = meshVolume(cubeMesh())
        XCTAssertEqual(originalVolume, 8000, accuracy: 1)

        let results = try SlicingEngine.cutModel(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            planePoints: horizontalPlane(atZ: 7), cutMode: .both)
        XCTAssertEqual(results.count, 2)
        let summedVolume = results.reduce(Float(0)) { $0 + meshVolume($1.mesh) }
        XCTAssertEqual(summedVolume, originalVolume, accuracy: 1)
    }

    /// Each real resulting piece's own volume must match its expected
    /// geometric share (7/20 and 13/20 of the cube for a Z=7 cut) — not
    /// just "the sum happens to work out", but each individual piece is
    /// the real correct shape.
    func testEachHalfHasTheCorrectIndividualVolume() throws {
        let results = try SlicingEngine.cutModel(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            planePoints: horizontalPlane(atZ: 7), cutMode: .both)
        let volumes = results.map { meshVolume($0.mesh) }.sorted()
        XCTAssertEqual(volumes.count, 2)
        XCTAssertEqual(volumes[0], 20 * 20 * 7, accuracy: 1, "smaller (lower) piece volume")
        XCTAssertEqual(volumes[1], 20 * 20 * 13, accuracy: 1, "larger (upper) piece volume")
    }

    /// Real per-result world-space SIZE (not position — see class doc)
    /// must match the expected split dimensions: one piece 20x20x7, the
    /// other 20x20x13, both with the cube's full 20x20 XY footprint.
    /// This is translation-independent so it's robust to the real
    /// engine's own post-cut recentering, but it DOES exercise the
    /// matrix16 bug fix: applying a garbage/identity transform to the
    /// recentered local mesh would still happen to produce a correctly-
    /// sized bounding box here only by coincidence of translation not
    /// affecting size — the position/adjacency test below is what
    /// catches a wrong *transform*.
    func testEachHalfHasTheCorrectWorldSpaceSize() throws {
        let results = try SlicingEngine.cutModel(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            planePoints: horizontalPlane(atZ: 7), cutMode: .both)
        let sizes = results.map { r -> SIMD3<Float> in
            let (lo, hi) = worldBoundingBox(r.mesh, r.transform)
            return hi - lo
        }.sorted { $0.z < $1.z }
        XCTAssertEqual(sizes.count, 2)
        assertEqual(sizes[0], SIMD3(20, 20, 7), accuracy: 0.01)
        assertEqual(sizes[1], SIMD3(20, 20, 13), accuracy: 0.01)
    }

    /// The real matrix16 fix must make the returned instance transform
    /// translation-EQUIVARIANT: cutting the same object translated by
    /// some `T` must shift each real resulting piece's own world
    /// position by exactly `T` relative to cutting it un-translated —
    /// this must hold for ANY correct implementation regardless of
    /// upstream's own (intentional, documented in the class doc)
    /// per-piece recentering formula, and is exactly the property the
    /// two real bugs fixed this session would break: a dropped
    /// `matrix16` makes the delta (0,0,0) instead of `T`; a
    /// double-applied instance transform (the `obj.mesh()` bug) makes
    /// the delta `2T` instead of `T`.
    func testCutResultsAreTranslationEquivariant() throws {
        let offset = SIMD3<Float>(50, 50, 0)
        let baseline = try SlicingEngine.cutModel(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            planePoints: horizontalPlane(atZ: 7), cutMode: .both)
        let shifted = try SlicingEngine.cutModel(
            objects: [(mesh: cubeMesh(), transform: translation(offset))],
            planePoints: horizontalPlane(atZ: 7).map { ($0.0 + offset.x, $0.1 + offset.y, $0.2 + offset.z) },
            cutMode: .both)
        XCTAssertEqual(baseline.count, 2)
        XCTAssertEqual(shifted.count, 2)

        // Match baseline/shifted pairs by their (translation-invariant)
        // own volume, since cutMode: .both doesn't guarantee result order.
        let baselineByVolume = baseline.sorted { meshVolume($0.mesh) < meshVolume($1.mesh) }
        let shiftedByVolume = shifted.sorted { meshVolume($0.mesh) < meshVolume($1.mesh) }

        for (b, s) in zip(baselineByVolume, shiftedByVolume) {
            XCTAssertEqual(meshVolume(b.mesh), meshVolume(s.mesh), accuracy: 0.5)
            let baseCenter = worldBoundingBox(b.mesh, b.transform)
            let shiftedCenter = worldBoundingBox(s.mesh, s.transform)
            let baseMid = (baseCenter.min + baseCenter.max) * 0.5
            let shiftedMid = (shiftedCenter.min + shiftedCenter.max) * 0.5
            assertEqual(shiftedMid - baseMid, offset, accuracy: 0.01)
        }
    }

    /// A cut plane entirely outside the mesh (Z=25, above a 20mm cube),
    /// keeping only the lower half, must return the whole cube untouched
    /// (full volume and size preserved) — the real engine's own
    /// degenerate-cut handling, not a special case in Swift.
    func testCutPlaneOutsideMeshKeepsWholeObjectIntact() throws {
        let results = try SlicingEngine.cutModel(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            planePoints: horizontalPlane(atZ: 25), cutMode: .lowerOnly)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(meshVolume(results[0].mesh), 8000, accuracy: 1)
        let (lo, hi) = worldBoundingBox(results[0].mesh, results[0].transform)
        assertEqual(hi - lo, SIMD3(20, 20, 20), accuracy: 0.01)
    }

    /// P4-006 integration: a real Plug connector must be materialized
    /// into the returned cut geometry, not just drawn as a viewport
    /// preview. Its toleranced female hole subtracts material from one
    /// half while its matching male peg protrudes from the other; the
    /// exposed peg volume means combined printed geometry is measurably
    /// GREATER than the unmodified cube (the actual physical connector
    /// pair, not a config echo or fake preview).
    func testPlugConnectorBakesTolerancedHoleAndPegIntoCutResults() throws {
        let originalVolume = meshVolume(cubeMesh())
        let preset = ConnectorPreset(
            type: .plug, style: .prizm, shape: .circle,
            radius: 3, height: 10, radiusTolerance: 0.5, heightTolerance: 1
        )
        let results = try SlicingEngine.cutModel(
            objects: [(mesh: cubeMesh(), transform: matrix_identity_float4x4)],
            planePoints: horizontalPlane(atZ: 10),
            cutMode: .both,
            connectors: [(position: SIMD3(10, 10, 10), normal: SIMD3(0, 0, 1), preset: preset)]
        )

        XCTAssertEqual(results.count, 2)
        let connectorVolume = results.reduce(Float(0)) { $0 + meshVolume($1.mesh) }
        XCTAssertGreaterThan(connectorVolume, originalVolume + 1, "real connector peg/hole must alter returned cut geometry")
    }
}

private func assertEqual(_ a: SIMD3<Float>, _ b: SIMD3<Float>, accuracy: Float, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.x, b.x, accuracy: accuracy, "x", file: file, line: line)
    XCTAssertEqual(a.y, b.y, accuracy: accuracy, "y", file: file, line: line)
    XCTAssertEqual(a.z, b.z, accuracy: accuracy, "z", file: file, line: line)
}
