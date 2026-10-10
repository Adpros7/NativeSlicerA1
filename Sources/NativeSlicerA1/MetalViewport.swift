import SwiftUI
import MetalKit

/// Minimal MTKView-backed viewport. Clears to a fixed background for now;
/// P1-006/P1-009 will feed it real mesh/toolpath vertex buffers once the
/// slicing engine bridge (P1-003) exists.
final class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct MetalViewport: NSViewRepresentable {
    func makeCoordinator() -> MetalRenderer {
        guard let renderer = MetalRenderer() else {
            fatalError("No Metal-capable device available")
        }
        return renderer
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.clearColor = MTLClearColorMake(0.12, 0.12, 0.14, 1.0)
        view.delegate = context.coordinator
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}
}
