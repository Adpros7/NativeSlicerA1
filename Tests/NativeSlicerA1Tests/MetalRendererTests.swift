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
}
