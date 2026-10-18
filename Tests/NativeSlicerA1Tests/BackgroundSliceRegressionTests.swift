import XCTest
import simd
@testable import NativeSlicerA1

/// Regression test for P2-009. The real root cause (found via `lldb`,
/// not inferred): `withNSA1ConfigEntries`/`withNSA1SceneObjects`
/// (`SlicingEngineBridge.swift`) used a recursive continuation-passing
/// helper that added several stack frames per array element — flattening
/// the ~435-entry full engine config this way needed 2,000+ stack
/// frames, fitting on the ~8MB main-thread stack but overflowing a GCD
/// worker thread's much smaller default stack (observed as a real
/// SIGBUS from both `Task.detached` and `DispatchQueue.global()`). Fixed
/// by rewriting those helpers to use manually-owned heap buffers with
/// O(1) stack depth regardless of array size — this test proves a real
/// slice completes from both GCD execution contexts without crashing or
/// hanging, pinned so neither helper regresses back to recursion.
final class BackgroundSliceRegressionTests: XCTestCase {
    private func cubeMesh(size: Float = 20) -> LoadedMesh {
        let v: [Float] = [
            0, 0, 0, size, 0, 0, size, size, 0, 0, size, 0,
            0, 0, size, size, 0, size, size, size, size, 0, size, size,
        ]
        let i: [UInt32] = [
            0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7,
            0, 4, 7, 0, 7, 1, 1, 7, 6, 1, 6, 2,
            2, 6, 5, 2, 5, 3, 4, 0, 3, 4, 3, 5,
        ]
        return LoadedMesh(vertices: v, indices: i)
    }

    func testSliceFromTaskDetachedCompletesWithoutCrashing() async throws {
        let mesh = cubeMesh()
        let loader = try BambuProfileLoader()
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).gcode").path
        let segments = try await Task.detached {
            try SlicingJob.slice(
                objects: [(mesh: mesh, transform: matrix_identity_float4x4)],
                loader: loader, outputPath: outputPath)
        }.value
        XCTAssertFalse(segments.isEmpty)
    }

    func testSliceFromDispatchQueueGlobalCompletesWithoutCrashing() throws {
        let mesh = cubeMesh()
        let loader = try BambuProfileLoader()
        let sem = DispatchSemaphore(value: 0)
        var sliceError: Error?
        var segmentCount = 0
        DispatchQueue.global().async {
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).gcode").path
            do {
                let segments = try SlicingJob.slice(
                    objects: [(mesh: mesh, transform: matrix_identity_float4x4)],
                    loader: loader, outputPath: outputPath)
                segmentCount = segments.count
            } catch {
                sliceError = error
            }
            sem.signal()
        }
        XCTAssertEqual(sem.wait(timeout: .now() + 20), .success, "slice() did not complete within 20s on DispatchQueue.global()")
        XCTAssertNil(sliceError)
        XCTAssertGreaterThan(segmentCount, 0)
    }

    /// Exercises `ProjectDocument.slice()` itself (the UI's real Slice
    /// button codepath, `Task { await document.slice() } }` in
    /// `ContentView.swift`), not just the lower-level `SlicingJob.slice`.
    @MainActor
    func testProjectDocumentSliceCompletesWithoutFreezingCaller() async throws {
        let document = ProjectDocument()
        let stlURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).stl")
        try SlicingEngine.storeSTL(atPath: stlURL.path, mesh: cubeMesh())
        document.importModel(at: stlURL)
        try? FileManager.default.removeItem(at: stlURL)

        await document.slice()

        XCTAssertNil(document.lastError)
        XCTAssertFalse(document.isSlicing)
        XCTAssertFalse(document.toolpath.isEmpty)
    }
}
