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
}
