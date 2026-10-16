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

/// Must mirror `ToolpathUniforms` in `Shaders.swift`'s MSL source.
private struct ToolpathUniforms {
    var modelViewProjection: simd_float4x4
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
    private let toolpathPipelineState: MTLRenderPipelineState
    private var meshBuffers: [UUID: GPUMesh] = [:]
    private var toolpathBuffer: MTLBuffer?
    private var toolpathVertexCount = 0
    /// P4-006 interactive cut-plane wireframe overlay, uploaded by
    /// `setCutPlane` and drawn with the same line-list pipeline as the
    /// toolpath (just a distinct color), no new pipeline state needed.
    private var cutPlaneBuffer: MTLBuffer?
    private var cutPlaneVertexCount = 0

    var renderObjects: [RenderObject] = []
    var camera = Camera()

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }

        guard
            let library = try? device.makeLibrary(source: viewportShaderSource, options: nil),
            let vertexFunction = library.makeFunction(name: "viewport_vertex"),
            let fragmentFunction = library.makeFunction(name: "viewport_fragment"),
            let toolpathVertexFunction = library.makeFunction(name: "toolpath_vertex"),
            let toolpathFragmentFunction = library.makeFunction(name: "toolpath_fragment")
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

        // Toolpath line vertices interleave position (float3) + color
        // (float3) — see `ToolpathVertex` below and `toolpath_vertex` in
        // Shaders.swift.
        let toolpathVertexDescriptor = MTLVertexDescriptor()
        toolpathVertexDescriptor.attributes[0].format = .float3
        toolpathVertexDescriptor.attributes[0].offset = 0
        toolpathVertexDescriptor.attributes[0].bufferIndex = 0
        toolpathVertexDescriptor.attributes[1].format = .float3
        toolpathVertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 3
        toolpathVertexDescriptor.attributes[1].bufferIndex = 0
        toolpathVertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 6

        let toolpathPipelineDescriptor = MTLRenderPipelineDescriptor()
        toolpathPipelineDescriptor.vertexFunction = toolpathVertexFunction
        toolpathPipelineDescriptor.fragmentFunction = toolpathFragmentFunction
        toolpathPipelineDescriptor.vertexDescriptor = toolpathVertexDescriptor
        toolpathPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        toolpathPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true

        guard
            let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor),
            let toolpathPipelineState = try? device.makeRenderPipelineState(descriptor: toolpathPipelineDescriptor),
            let depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
        else { return nil }

        self.device = device
        commandQueue = queue
        self.pipelineState = pipelineState
        self.toolpathPipelineState = toolpathPipelineState
        self.depthState = depthState
    }

    /// Uploads a real-geometry toolpath (P1-009, `SlicingJob.slice`'s
    /// return value) as a GPU line-list buffer: two colored vertices per
    /// segment. When `viewMode` is nil (default), uses the original
    /// hardcoded extrude=orange/travel=gray coloring. When set, computes
    /// per-mode colors from the segment's real engine data.
    /// Replaces any previously uploaded toolpath.
    func setToolpath(_ segments: [ToolpathSegment], viewMode: ToolpathViewMode? = nil) {
        guard !segments.isEmpty else {
            toolpathBuffer = nil
            toolpathVertexCount = 0
            return
        }
        var floats: [Float] = []
        floats.reserveCapacity(segments.count * 12)
        for seg in segments {
            let color: SIMD3<Float> = viewMode.map { seg.color(for: $0) } ?? (seg.isTravel ? SIMD3(0.6, 0.6, 0.6) : SIMD3(0.95, 0.55, 0.15))
            floats.append(contentsOf: [seg.start.x, seg.start.y, seg.start.z, color.x, color.y, color.z])
            floats.append(contentsOf: [seg.end.x, seg.end.y, seg.end.z, color.x, color.y, color.z])
        }
        toolpathBuffer = device.makeBuffer(bytes: floats, length: floats.count * MemoryLayout<Float>.stride, options: .storageModeShared)
        toolpathVertexCount = segments.count * 2
    }

    /// Uploads the P4-006 interactive cut-plane wireframe (quad outline
    /// + normal indicator) as a GPU line-list buffer, same vertex layout
    /// as the toolpath buffer (position + color interleaved). `nil`
    /// clears it (not in cut-plane mode / no object selected).
    func setCutPlane(_ plane: CutPlane?) {
        guard let plane else {
            cutPlaneBuffer = nil
            cutPlaneVertexCount = 0
            return
        }
        let color = SIMD3<Float>(0.2, 0.9, 0.95) // cyan, distinct from toolpath/mesh colors
        var floats: [Float] = []
        let segments = plane.wireframeSegments
        floats.reserveCapacity(segments.count * 12)
        for (a, b) in segments {
            floats.append(contentsOf: [a.x, a.y, a.z, color.x, color.y, color.z])
            floats.append(contentsOf: [b.x, b.y, b.z, color.x, color.y, color.z])
        }
        cutPlaneBuffer = device.makeBuffer(bytes: floats, length: floats.count * MemoryLayout<Float>.stride, options: .storageModeShared)
        cutPlaneVertexCount = segments.count * 2
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

        if let toolpathBuffer, toolpathVertexCount > 0 {
            var toolpathUniforms = ToolpathUniforms(modelViewProjection: viewProjection)
            encoder.setRenderPipelineState(toolpathPipelineState)
            encoder.setVertexBuffer(toolpathBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&toolpathUniforms, length: MemoryLayout<ToolpathUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: toolpathVertexCount)
        }

        if let cutPlaneBuffer, cutPlaneVertexCount > 0 {
            var cutPlaneUniforms = ToolpathUniforms(modelViewProjection: viewProjection)
            encoder.setRenderPipelineState(toolpathPipelineState)
            encoder.setVertexBuffer(cutPlaneBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&cutPlaneUniforms, length: MemoryLayout<ToolpathUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: cutPlaneVertexCount)
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
    /// P3-005: when true, clicks/drags paint instead of orbiting.
    var isPaintMode = false
    /// Called with the click/drag location in this view's own
    /// (top-left-origin, AppKit-flipped) coordinate space.
    var onPaintStroke: ((CGPoint) -> Void)?
    /// P4-006: when true, clicks/drags reposition the cut plane instead
    /// of orbiting (mirrors `isPaintMode`'s routing).
    var isCutPlaneMode = false
    var onCutPlaneClick: ((CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isPaintMode { onPaintStroke?(flippedLocation(of: event)); return }
        if isCutPlaneMode { onCutPlaneClick?(flippedLocation(of: event)) }
    }

    override func mouseDragged(with event: NSEvent) {
        if isPaintMode {
            onPaintStroke?(flippedLocation(of: event))
            return
        }
        if isCutPlaneMode {
            onCutPlaneClick?(flippedLocation(of: event))
            return
        }
        let sensitivity: Float = 0.01
        onOrbit?(Float(event.deltaX) * sensitivity, Float(event.deltaY) * sensitivity)
    }

    /// `NSView`'s event location is bottom-left-origin; `screenPointToRay`
    /// expects top-left-origin (matching typical screen/UIKit convention).
    private func flippedLocation(of event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: bounds.height - p.y)
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
        view.onPaintStroke = { [weak renderer, weak view] screenPoint in
            guard let renderer, let view,
                  let selectedID = document.selection,
                  let object = document.objects.first(where: { $0.id == selectedID }),
                  let mesh = document.mesh(for: object)
            else { return }
            let ray = screenPointToRay(screenPoint: screenPoint, viewSize: view.bounds.size, camera: renderer.camera)
            // Transform the world-space ray into the object's local mesh
            // space (inverse of its placement transform) so the real
            // Möller–Trumbore test operates in the same space as the
            // mesh's own vertex data.
            let inverseTransform = object.transform.matrix.inverse
            let localOrigin4 = inverseTransform * SIMD4(ray.origin, 1)
            let localOrigin = SIMD3(localOrigin4.x, localOrigin4.y, localOrigin4.z) / localOrigin4.w
            let localDir4 = inverseTransform * SIMD4(ray.direction, 0)
            let localDir = normalize(SIMD3(localDir4.x, localDir4.y, localDir4.z))
            guard let hit = rayMeshIntersection(origin: localOrigin, direction: localDir, mesh: mesh) else { return }
            document.paintAt(objectID: selectedID, localPoint: hit)
        }
        view.onCutPlaneClick = { [weak renderer, weak view] screenPoint in
            guard let renderer, let view,
                  let selectedID = document.selection,
                  let object = document.objects.first(where: { $0.id == selectedID }),
                  let mesh = document.mesh(for: object)
            else { return }
            let ray = screenPointToRay(screenPoint: screenPoint, viewSize: view.bounds.size, camera: renderer.camera)
            let inverseTransform = object.transform.matrix.inverse
            let localOrigin4 = inverseTransform * SIMD4(ray.origin, 1)
            let localOrigin = SIMD3(localOrigin4.x, localOrigin4.y, localOrigin4.z) / localOrigin4.w
            let localDir4 = inverseTransform * SIMD4(ray.direction, 0)
            let localDir = normalize(SIMD3(localDir4.x, localDir4.y, localDir4.z))
            guard let localHit = rayMeshIntersection(origin: localOrigin, direction: localDir, mesh: mesh) else { return }
            // The cut plane lives in world space (matching
            // `SlicingEngine.cutModel`'s plane-point convention), so the
            // local mesh hit must be transformed back out.
            let worldHit4 = object.transform.matrix * SIMD4(localHit, 1)
            let worldHit = SIMD3(worldHit4.x, worldHit4.y, worldHit4.z) / worldHit4.w
            document.setCutPlaneCenter(worldHit)
        }
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
        let vm = document.toolpathViewMode
        renderer.setToolpath(document.toolpath, viewMode: vm)
        nsView.isPaintMode = document.paintMode
        nsView.isCutPlaneMode = document.cutPlaneMode
        renderer.setCutPlane(document.cutPlaneMode ? document.cutPlane : nil)
    }
}
