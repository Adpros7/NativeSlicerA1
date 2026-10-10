import SwiftUI
import MetalKit
import simd

/// GPU-side buffer pair for one imported mesh, built once (not per frame)
/// and cached by the mesh's scene id.
private struct GPUMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
}

/// One placed object as the renderer needs it: its GPU mesh id, world
/// transform, and whether to draw it highlighted.
struct RenderObject {
    let id: UUID
    let meshID: UUID
    let transform: simd_float4x4
    let selected: Bool
}

/// Must mirror `Uniforms` in `Shaders.swift`'s MSL source byte-for-byte:
/// two column-major 4x4 matrices then a float4, all 16-byte aligned on
/// both sides, so no manual padding is needed.
private struct Uniforms {
    var modelViewProjection: simd_float4x4
    var model: simd_float4x4
    var color: SIMD4<Float>
}

/// Renders imported STL/3MF geometry (P1-004/P1-005) with an orbit camera.
/// Mesh buffers are uploaded once per imported mesh and cached; only the
/// small per-object uniform struct is rebuilt per draw call.
final class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var meshBuffers: [UUID: GPUMesh] = [:]

    var renderObjects: [RenderObject] = []
    var camera = Camera()

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }

        guard
            let library = try? device.makeLibrary(source: viewportShaderSource, options: nil),
            let vertexFunction = library.makeFunction(name: "viewport_vertex"),
            let fragmentFunction = library.makeFunction(name: "viewport_fragment")
        else { return nil }

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 3

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true

        guard
            let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor),
            let depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
        else { return nil }

        self.device = device
        commandQueue = queue
        self.pipelineState = pipelineState
        self.depthState = depthState
    }

    /// Uploads a GPU buffer pair for `mesh` if `meshID` isn't cached yet.
    func ensureBuffer(for meshID: UUID, mesh: LoadedMesh) {
        guard meshBuffers[meshID] == nil else { return }
        guard
            let vertexBuffer = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * MemoryLayout<Float>.stride, options: .storageModeShared),
            let indexBuffer = device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else { return }
        meshBuffers[meshID] = GPUMesh(vertexBuffer: vertexBuffer, indexBuffer: indexBuffer, indexCount: mesh.indices.count)
    }

    /// Drops GPU buffers for meshes no longer referenced by the scene
    /// (e.g. after `ProjectDocument.removeObject` or a project reload).
    func pruneBuffers(keeping liveMeshIDs: Set<UUID>) {
        meshBuffers = meshBuffers.filter { liveMeshIDs.contains($0.key) }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)

        let aspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
        let viewProjection = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix

        for object in renderObjects {
            guard let gpuMesh = meshBuffers[object.meshID] else { continue }
            var uniforms = Uniforms(
                modelViewProjection: viewProjection * object.transform,
                model: object.transform,
                color: object.selected ? SIMD4(0.95, 0.65, 0.25, 1.0) : SIMD4(0.55, 0.6, 0.68, 1.0)
            )
            encoder.setVertexBuffer(gpuMesh.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: gpuMesh.indexCount, indexType: .uint32, indexBuffer: gpuMesh.indexBuffer, indexBufferOffset: 0)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

/// `MTKView` subclass forwarding mouse-drag orbit and scroll-wheel zoom
/// gestures — the standard AppKit event path, no gesture-recognizer
/// dependency needed for two inputs this simple.
final class OrbitMTKView: MTKView {
    var onOrbit: ((Float, Float) -> Void)?
    var onZoom: ((Float) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDragged(with event: NSEvent) {
        let sensitivity: Float = 0.01
        onOrbit?(Float(event.deltaX) * sensitivity, Float(event.deltaY) * sensitivity)
    }

    override func scrollWheel(with event: NSEvent) {
        let factor: Float = 1 + Float(event.scrollingDeltaY) * 0.01
        onZoom?(factor)
    }
}

struct MetalViewport: NSViewRepresentable {
    @ObservedObject var document: ProjectDocument

    func makeCoordinator() -> MetalRenderer {
        guard let renderer = MetalRenderer() else {
            fatalError("No Metal-capable device available")
        }
        return renderer
    }

    func makeNSView(context: Context) -> OrbitMTKView {
        let view = OrbitMTKView(frame: .zero, device: context.coordinator.device)
        view.clearColor = MTLClearColorMake(0.12, 0.12, 0.14, 1.0)
        view.depthStencilPixelFormat = .depth32Float
        view.clearDepth = 1.0
        view.delegate = context.coordinator
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        let renderer = context.coordinator
        view.onOrbit = { [weak renderer] deltaAzimuth, deltaElevation in
            renderer?.camera.orbit(deltaAzimuth: deltaAzimuth, deltaElevation: deltaElevation)
        }
        view.onZoom = { [weak renderer] factor in renderer?.camera.zoom(by: factor) }
        return view
    }

    func updateNSView(_ nsView: OrbitMTKView, context: Context) {
        let renderer = context.coordinator
        for object in document.objects {
            if let mesh = document.mesh(for: object) {
                renderer.ensureBuffer(for: object.sourceMeshID, mesh: mesh)
            }
        }
        renderer.pruneBuffers(keeping: Set(document.objects.map(\.sourceMeshID)))
        renderer.renderObjects = document.objects.map {
            RenderObject(id: $0.id, meshID: $0.sourceMeshID, transform: $0.transform.matrix, selected: $0.id == document.selection)
        }
    }
}
