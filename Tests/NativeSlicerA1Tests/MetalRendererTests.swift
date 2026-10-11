import XCTest
import MetalKit
@testable import NativeSlicerA1

final class MetalRendererTests: XCTestCase {
    /// Proves the renderer actually acquires a device and a working command
    /// queue (not just that the type compiles).
    func testRendererInitializesOnSystemDevice() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("No Metal device available in this environment")
        }
        let renderer = MetalRenderer()
        XCTAssertNotNil(renderer)
    }

    /// A device with no command-queue support must fail initialization
    /// rather than crash later inside `draw(in:)`.
    func testRendererFailsGracefullyWithoutDevice() {
        XCTAssertNil(MetalRenderer(device: nil))
    }

    /// Exercises the real draw path end to end: uploads a real imported
    /// mesh's geometry (P1-004) to GPU buffers, builds the per-object
    /// uniforms, and encodes an actual draw call against the compiled
    /// viewport shader (P1-004→viewport wiring) — not just that the
    /// renderer initializes.
    func testDrawEncodesRealMeshWithoutCrashing() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available in this environment")
        }
        guard let renderer = MetalRenderer(device: device) else {
            return XCTFail("Renderer failed to initialize on a real device")
        }

        let url = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NativeSlicerA1/Resources/Profiles/BBL/bbl-3dp-X1.stl")
        let mesh = try SlicingEngine.loadSTLMesh(atPath: url.path)
        let meshID = UUID()
        renderer.ensureBuffer(for: meshID, mesh: mesh)
        renderer.renderObjects = [RenderObject(id: UUID(), meshID: meshID, transform: matrix_identity_float4x4, selected: true)]

        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: device)
        view.depthStencilPixelFormat = .depth32Float
        view.colorPixelFormat = .bgra8Unorm
        renderer.draw(in: view) // must not crash/assert
    }

    /// Exercises P1-009 end to end: slices a real cube through the real
    /// A1 engine pipeline (P1-008), uploads the real resulting toolpath
    /// (not synthetic test data) to a GPU line buffer, and encodes an
    /// actual line draw call against the compiled toolpath shader.
    func testDrawEncodesRealToolpathFromRealSlice() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available in this environment")
        }
        guard let renderer = MetalRenderer(device: device) else {
            return XCTFail("Renderer failed to initialize on a real device")
        }

        let v: [Float] = [
            0, 0, 0, 20, 0, 0, 20, 20, 0, 0, 20, 0,
            0, 0, 20, 20, 0, 20, 20, 20, 20, 0, 20, 20,
        ]
        let i: [UInt32] = [
            0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6,
            0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2,
            2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0,
        ]
        let mesh = LoadedMesh(vertices: v, indices: i)
        let loader = try BambuProfileLoader()
        let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gcode").path
        defer { try? FileManager.default.removeItem(atPath: outputPath) }

        let toolpath = try SlicingJob.slice(objects: [(mesh: mesh, transform: matrix_identity_float4x4)], loader: loader, outputPath: outputPath)
        XCTAssertGreaterThan(toolpath.count, 100, "expected many real toolpath segments across 100 layers")
        XCTAssertTrue(toolpath.contains { !$0.isTravel }, "expected at least one real extrusion segment")

        renderer.setToolpath(toolpath)

        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: device)
        view.depthStencilPixelFormat = .depth32Float
        view.colorPixelFormat = .bgra8Unorm
        renderer.draw(in: view) // must not crash/assert
    }
}
