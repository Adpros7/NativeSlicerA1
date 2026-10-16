import CSlic3rBridge
import Foundation
import simd

enum SlicingEngineError: Error {
    case failedToReadSTL(path: String)
    case failedToRead3MF(path: String)
    case failedToWrite3MF(path: String)
    case objectIndexOutOfRange(path: String, index: Int)
    case unsupportedFileType(String)
    case failedToWriteSTL(path: String, message: String)
    case failedToReadOBJ(path: String)
    case failedToWriteOBJ(path: String, message: String)
    case sliceFailed(String)
    case failedToReadSTEP(path: String)
}

/// One real toolpath line segment from the engine's own
/// `GCodeProcessorResult` (P1-009) — the same per-move data BambuStudio's
/// own G-code preview consumes.
/// View modes for G-code toolpath coloring (P1-012). Matches upstream
/// `EViewType` from `GCodeRenderer`: `FeatureType`, `Height`,
/// `Feedrate`, `Temperature`, `LayerTime`, `Tool`.
enum ToolpathViewMode: String, CaseIterable, Identifiable {
    case featureType = "Feature Type"
    case height = "Layer Height"
    case feedrate = "Feed Rate"
    case temperature = "Temperature"
    case layerTime = "Layer Time"
    case tool = "Tool"

    var id: String { rawValue }
}
struct ToolpathSegment {
    let start: SIMD3<Float>
    let end: SIMD3<Float>
    let width: Float
    let height: Float
    let isTravel: Bool
    /// Extrusion feed rate in mm/min (0 for travel moves).
    let feedrate: Float
    /// Nozzle temperature in °C (0 if not set).
    let temperature: Float
    /// Layer time in seconds (0 if not set).
    let layerDuration: Float
    /// Extruder ID (0-based index).
    let extruderID: Int32
    /// Extrusion role: raw upstream `ExtrusionRole` enum value — 0=None,
    /// 1=Perimeter, 2=ExternalPerimeter, 3=OverhangPerimeter,
    /// 4=InternalInfill, 5=SolidInfill, 6=FloatingVerticalShell,
    /// 7=TopSolidInfill, 8=BottomSurface, 9=Ironing, 10=BridgeInfill,
    /// 11=GapFill, 12=Skirt, 13=Brim, 14=SupportMaterial,
    /// 15=SupportMaterialInterface, 16=SupportTransition,
    /// 17=SupportIroning, 18=WipeTower, 19=Custom, 20=Flush, 21=Mixed
    /// (`ExtrusionEntity.hpp`'s `ExtrusionRole`; `CSlic3rBridge.cpp`
    /// casts the raw enum value directly, no remapping).
    let extrusionRole: Float

    /// Computes a color for this segment based on the given view mode.
    /// Uses the same upstream approach: min-max normalized colormap
    /// (viridis-like) with logarithmic scaling for layer time.
    func color(for viewMode: ToolpathViewMode) -> SIMD3<Float> {
        switch viewMode {
        case .featureType:
            return extrusionRoleColor()
        case .height:
            return normalizedColor(height, minVal: 0.05, maxVal: 1.0)
        case .feedrate:
            return normalizedColor(feedrate, minVal: 50, maxVal: 5000)
        case .temperature:
            return normalizedColor(temperature, minVal: 180, maxVal: 260)
        case .layerTime:
            return normalizedLogColor(layerDuration, minVal: 0.1, maxVal: 30)
        case .tool:
            return toolColor()
        }
    }

    private func extrusionRoleColor() -> SIMD3<Float> {
        // Exact upstream `BaseRenderer::Extrusion_Role_Colors` table
        // (`GCodeRenderer/BaseRenderer.cpp`), indexed by the raw
        // `ExtrusionRole` enum value (see `extrusionRole`'s doc comment).
        let colors: [SIMD3<Float>] = [
            SIMD3(0.90, 0.70, 0.70), // erNone
            SIMD3(1.00, 0.90, 0.30), // erPerimeter
            SIMD3(1.00, 0.49, 0.22), // erExternalPerimeter
            SIMD3(0.12, 0.12, 1.00), // erOverhangPerimeter
            SIMD3(0.69, 0.19, 0.16), // erInternalInfill
            SIMD3(0.59, 0.33, 0.80), // erSolidInfill
            SIMD3(0.90, 0.70, 0.70), // erFloatingVerticalShell
            SIMD3(0.94, 0.25, 0.25), // erTopSolidInfill
            SIMD3(0.40, 0.36, 0.78), // erBottomSurface
            SIMD3(1.00, 0.55, 0.41), // erIroning
            SIMD3(0.30, 0.50, 0.73), // erBridgeInfill
            SIMD3(1.00, 1.00, 1.00), // erGapFill
            SIMD3(0.00, 0.53, 0.43), // erSkirt
            SIMD3(0.00, 0.23, 0.43), // erBrim
            SIMD3(0.00, 1.00, 0.00), // erSupportMaterial
            SIMD3(0.00, 0.50, 0.00), // erSupportMaterialInterface
            SIMD3(0.00, 0.25, 0.00), // erSupportTransition
            SIMD3(0.60, 1.00, 0.60), // erSupportIroning
            SIMD3(0.70, 0.89, 0.67), // erWipeTower
            SIMD3(0.37, 0.82, 0.58), // erCustom
            SIMD3(0.85, 0.65, 0.95), // erFlush
        ]
        let index = Int(extrusionRole)
        guard index >= 0, index < colors.count else { return SIMD3(0.6, 0.6, 0.6) }
        return colors[index]
    }

    private func toolColor() -> SIMD3<Float> {
        // Per-tool colors: cycle through distinct hues.
        let hues: [SIMD3<Float>] = [
            SIMD3(0.95, 0.55, 0.15),  // orange (default extrude)
            SIMD3(0.2, 0.6, 0.9),    // blue
            SIMD3(0.3, 0.8, 0.3),    // green
            SIMD3(0.9, 0.2, 0.5),    // pink
            SIMD3(0.8, 0.8, 0.2),    // yellow
            SIMD3(0.5, 0.3, 0.8),    // purple
        ]
        return hues[Int(extruderID) % hues.count]
    }

    /// Maps a value through a viridis-like colormap (min→purple, max→yellow).
    private func normalizedColor(_ value: Float, minVal: Float, maxVal: Float) -> SIMD3<Float> {
        let t = max(0, min(1, (value - minVal) / max(0.001, maxVal - minVal)))
        return viridisColor(t)
    }

    /// Logarithmic version: maps log(value) through the colormap.
    private func normalizedLogColor(_ value: Float, minVal: Float, maxVal: Float) -> SIMD3<Float> {
        let minLog = log(max(0.001, minVal))
        let maxLog = log(max(0.001, maxVal))
        let t = max(0, min(1, (log(max(0.001, value)) - minLog) / max(0.001, maxLog - minLog)))
        return viridisColor(t)
    }

    /// Viridis colormap approximation (public-domain, from igl/colormap.cpp).
    /// Maps t ∈ [0,1] to an RGB color: purple→blue→green→yellow.
    private func viridisColor(_ t: Float) -> SIMD3<Float> {
        // Simplified 5-segment piecewise approximation of the 256-entry viridis palette.
        let t3 = t * t
        let t4 = t3 * t
        // Close approximation: purple (0) → blue → green → yellow (1)
        let r: Float = 0.267 + 2.5 * t - 5.0 * t3 + 3.5 * t4
        let g: Float = 0.005 + 2.0 * t - 4.0 * t3 + 3.0 * t4
        let b: Float = 0.329 + 0.5 * t + 1.0 * t3 - 1.7 * t4
        return SIMD3(max(0, min(1, r)), max(0, min(1, g)), max(0, min(1, b)))
    }
}
/// A real-geometry mesh loaded through the engine bridge: flat vertex (XYZ
/// triples) and triangle index buffers, ready to upload to a Metal vertex
/// buffer.
struct LoadedMesh {
    let vertices: [Float] // XYZ triples
    let indices: [UInt32] // 3 per triangle
    var triangleCount: Int { indices.count / 3 }
}

private func convert(_ raw: UnsafeMutablePointer<NSA1Mesh>) -> LoadedMesh {
    defer { nsa1_free_mesh(raw) }
    let vertexFloatCount = raw.pointee.vertex_count * 3
    let vertices = Array(UnsafeBufferPointer(start: raw.pointee.vertices, count: vertexFloatCount))
    let indices = Array(UnsafeBufferPointer(start: raw.pointee.indices, count: raw.pointee.index_count))
    return LoadedMesh(vertices: vertices, indices: indices)
}

private func meshToUnsafeNSA1Mesh(_ mesh: LoadedMesh) -> UnsafeMutablePointer<NSA1Mesh> {
    let raw = UnsafeMutablePointer<NSA1Mesh>.allocate(capacity: 1)
    let vertexCount = mesh.vertices.count
    let indexCount = mesh.indices.count
    mesh.vertices.withUnsafeBufferPointer { vp in
        mesh.indices.withUnsafeBufferPointer { ip in
            raw.pointee = NSA1Mesh(
                vertices: UnsafePointer(vp.baseAddress),
                vertex_count: vertexCount,
                indices: UnsafePointer(ip.baseAddress),
                index_count: indexCount
            )
        }
    }
    return raw
}

/// Column-major flat form of a `simd_float4x4`, matching the C bridge's
/// `matrix16` convention (same layout `nsa1_3mf_object_matrix` returns).
private func flatten(_ m: simd_float4x4) -> [Double] {
    [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
        .flatMap { [$0.x, $0.y, $0.z, $0.w] }
        .map(Double.init)
}

private func unflatten(_ raw: UnsafeBufferPointer<Double>) -> simd_float4x4 {
    func column(_ base: Int) -> SIMD4<Float> {
        SIMD4(Float(raw[base]), Float(raw[base + 1]), Float(raw[base + 2]), Float(raw[base + 3]))
    }
    return simd_float4x4(columns: (column(0), column(4), column(8), column(12)))
}

/// One Z-height band with an overridden layer height (P4-014). `zMin`/
/// `zMax` are object-local Z in mm; matches upstream's `t_layer_height_range`
/// semantics exactly (consumed by the real engine's
/// `layer_height_profile_from_ranges`, not a reimplemented profile).
struct LayerHeightRange: Equatable, Sendable {
    var zMin: Double
    var zMax: Double
    var layerHeight: Double
}

private struct PendingSceneObject {
    let vertices: [Float]
    let indices: [UInt32]
    let matrix16: [Double]
    var paintData: [UInt8] = []
    var layerHeightRanges: [NSA1LayerHeightRange] = []
    /// P4-007 cut lineage — see `NSA1SceneObject.cut_group_id`.
    var cutGroupID: UInt64 = 0
}

/// Recursively pins each object's vertex/index/matrix/paint/layer-height-range
/// arrays with nested `withUnsafeBufferPointer` scopes so the flat
/// `NSA1SceneObject` array handed to `body` stays valid for the whole call —
/// the C function never outlives this stack frame, so no manual lifetime
/// management is needed. An empty `paintData` yields a NULL `paint_data`
/// pointer (unpainted object); an empty `layerHeightRanges` yields a NULL
/// `layer_height_ranges` pointer (uniform layer height, P4-014).
private func withNSA1SceneObjects<R>(_ pending: [PendingSceneObject], _ body: (UnsafePointer<NSA1SceneObject>?, Int) -> R) -> R {
    func build(_ index: Int, _ acc: inout [NSA1SceneObject]) -> R {
        guard index < pending.count else {
            return acc.withUnsafeBufferPointer { body($0.baseAddress, acc.count) }
        }
        let object = pending[index]
        return object.vertices.withUnsafeBufferPointer { vbuf in
            object.indices.withUnsafeBufferPointer { ibuf in
                object.matrix16.withUnsafeBufferPointer { mbuf in
                    object.paintData.withUnsafeBufferPointer { pbuf in
                        object.layerHeightRanges.withUnsafeBufferPointer { lbuf in
                            acc.append(NSA1SceneObject(
                                vertices: vbuf.baseAddress, vertex_count: vbuf.count / 3,
                                indices: ibuf.baseAddress, index_count: ibuf.count,
                                matrix16: mbuf.baseAddress,
                                paint_data: pbuf.baseAddress, paint_data_size: pbuf.count,
                                layer_height_ranges: lbuf.baseAddress, layer_height_range_count: lbuf.count,
                                cut_group_id: object.cutGroupID
                            ))
                            return build(index + 1, &acc)
                        }
                    }
                }
            }
        }
    }
    var acc: [NSA1SceneObject] = []
    acc.reserveCapacity(pending.count)
    return build(0, &acc)
}

/// Pins each config entry's key/value C strings for the call, mirroring
/// `withNSA1SceneObjects`'s lifetime pattern.
private func withNSA1ConfigEntries<R>(_ pending: [(key: String, value: String)], _ body: (UnsafePointer<NSA1ConfigEntry>?, Int) -> R) -> R {
    func build(_ index: Int, _ acc: inout [NSA1ConfigEntry]) -> R {
        guard index < pending.count else {
            return acc.withUnsafeBufferPointer { body($0.baseAddress, acc.count) }
        }
        let entry = pending[index]
        return entry.key.withCString { kptr in
            entry.value.withCString { vptr in
                acc.append(NSA1ConfigEntry(key: kptr, value: vptr))
                return build(index + 1, &acc)
            }
        }
    }
    var acc: [NSA1ConfigEntry] = []
    acc.reserveCapacity(pending.count)
    return build(0, &acc)
}

/// Mirrors upstream's `nsa1_cut_model` numeric `cut_mode` convention
/// exactly (`CSlic3rBridge.h`: 0=both, 1=lower, 2=upper).
enum CutMode: Int32, CaseIterable, Sendable {
    case both = 0
    case lowerOnly = 1
    case upperOnly = 2
}

/// Thin Swift wrapper over the C-ABI bridge into the real, vendored
/// libslic3r (see ARCHITECTURE.md P0-005, RESEARCH.md P1-003). Proves the
/// Swift executable actually links and calls into the compiled slicing
/// engine, not a hand-rolled parser.
enum SlicingEngine {
    static func stlTriangleCount(atPath path: String) throws -> Int {
        let count = path.withCString { nsa1_stl_triangle_count($0) }
        guard count >= 0 else { throw SlicingEngineError.failedToReadSTL(path: path) }
        return Int(count)
    }

    /// Loads an STL file's full geometry via the real engine's
    /// `TriangleMesh::ReadSTLFile`, copying the result into Swift arrays.
    static func loadSTLMesh(atPath path: String) throws -> LoadedMesh {
        guard let raw = path.withCString({ nsa1_load_stl_mesh($0) }) else {
            throw SlicingEngineError.failedToReadSTL(path: path)
        }
        return convert(raw)
    }

    /// Writes a triangle mesh to a binary STL file via the real engine's
    /// `TriangleMesh::write_binary` (P1-010).
    static func storeSTL(atPath path: String, mesh: LoadedMesh) throws {
        let raw = meshToUnsafeNSA1Mesh(mesh)
        guard let rawPath = path.cString(using: .utf8) else {
            throw SlicingEngineError.unsupportedFileType("invalid path encoding")
        }
        var errorPtr: UnsafeMutablePointer<CChar>? = nil
        let result = nsa1_store_stl(rawPath, raw, &errorPtr)
        if let errorPtr {
            let msg = String(cString: errorPtr)
            nsa1_free_string(errorPtr)
            throw SlicingEngineError.failedToWriteSTL(path: path, message: msg)
        }
        guard result == 0 else { throw SlicingEngineError.failedToWriteSTL(path: path, message: "unknown error") }
    }

    /// Loads a binary STL file into a triangle mesh (P1-010).
    static func loadSTLMeshBinary(atPath path: String) throws -> LoadedMesh {
        guard let raw = path.cString(using: .utf8) else {
            throw SlicingEngineError.unsupportedFileType("invalid path encoding")
        }
        guard let mesh = nsa1_load_stl_mesh_binary(raw) else {
            throw SlicingEngineError.failedToReadSTL(path: path)
        }
        return convert(mesh)
    }

    /// Writes a triangle mesh to an OBJ file via the real engine's
    /// `TriangleMesh::WriteOBJFile` (P1-010).
    static func storeOBJ(atPath path: String, mesh: LoadedMesh) throws {
        let raw = meshToUnsafeNSA1Mesh(mesh)
        guard let rawPath = path.cString(using: .utf8) else {
            throw SlicingEngineError.unsupportedFileType("invalid path encoding")
        }
        var errorPtr: UnsafeMutablePointer<CChar>? = nil
        let result = nsa1_store_obj(rawPath, raw, &errorPtr)
        if let errorPtr {
            let msg = String(cString: errorPtr)
            nsa1_free_string(errorPtr)
            throw SlicingEngineError.failedToWriteOBJ(path: path, message: msg)
        }
        guard result == 0 else { throw SlicingEngineError.failedToWriteOBJ(path: path, message: "unknown error") }
    }

    static func loadOBJMesh(atPath path: String) throws -> LoadedMesh {
        guard let raw = path.cString(using: .utf8) else {
            throw SlicingEngineError.unsupportedFileType("invalid path encoding")
        }
        guard let mesh = nsa1_load_obj_mesh(raw) else {
            throw SlicingEngineError.failedToReadOBJ(path: path)
        }
        return convert(mesh)
    }

    /// Loads an STEP file into a triangle mesh via the real engine's
    /// `Step` class (OpenCascade tessellation, P1-010).
    static func loadSTEPMesh(atPath path: String) throws -> LoadedMesh {
        guard let raw = path.cString(using: .utf8) else {
            throw SlicingEngineError.unsupportedFileType("invalid path encoding")
        }
        guard let mesh = nsa1_load_step_mesh(raw) else {
            throw SlicingEngineError.failedToReadSTEP(path: path)
        }
        return convert(mesh)
    }

    /// Number of top-level model objects in a 3MF file, via the real
    /// engine's `load_3mf`.
    static func threeMFObjectCount(atPath path: String) throws -> Int {
        let count = path.withCString { nsa1_3mf_object_count($0) }
        guard count >= 0 else { throw SlicingEngineError.failedToRead3MF(path: path) }
        return Int(count)
    }

    /// Extracts the `unit` attribute from a 3MF file's `<model>` element.
    /// Returns "millimeter" (the 3MF spec default) if not found.
    static func threeMFUnit(atPath path: String) throws -> String {
        guard let raw = path.withCString({ nsa1_get_3mf_unit($0) }) else {
            return "millimeter"
        }
        defer { nsa1_free_string(raw) }
        return String(cString: raw)
    }

    /// Auto-orient: runs upstream orient() on a mesh, returns optimal rotation
    /// matrix (column-major 4x4) that minimizes overhang area.
    static func autoOrientMesh(_ mesh: LoadedMesh) throws -> simd_float4x4 {
        var matrix = [Double](repeating: 0, count: 16)
        let status = mesh.vertices.withUnsafeBufferPointer { vbuf in
            mesh.indices.withUnsafeBufferPointer { ibuf in
                nsa1_auto_orient(
                    vbuf.baseAddress,
                    Int(vbuf.count),
                    ibuf.baseAddress,
                    Int(ibuf.count),
                    &matrix
                )
            }
        }
        guard status == 0 else {
            throw SlicingEngineError.sliceFailed("auto-orient failed")
        }
        let m0 = SIMD4<Float>(Float(matrix[0]), Float(matrix[1]), Float(matrix[2]), Float(matrix[3]))
        let m1 = SIMD4<Float>(Float(matrix[4]), Float(matrix[5]), Float(matrix[6]), Float(matrix[7]))
        let m2 = SIMD4<Float>(Float(matrix[8]), Float(matrix[9]), Float(matrix[10]), Float(matrix[11]))
        let m3 = SIMD4<Float>(Float(matrix[12]), Float(matrix[13]), Float(matrix[14]), Float(matrix[15]))
        return simd_float4x4([m0, m1, m2, m3])
    }

    /// Auto-arranges objects on a rectangular bed (P4-011), via the real
    /// engine's libnest2d-backed `Slic3r::arrangement::arrange()` using
    /// each mesh's real 2D convex hull as its packing silhouette. Returns
    /// per-object (x, y) translation in mm and rotation in radians to
    /// apply on top of each object's existing XY placement, in input order.
    static func autoArrange(
        meshes: [(vertices: [Float], indices: [UInt32], matrix: simd_float4x4)],
        bedWidth: Double,
        bedHeight: Double,
        clearance: Double
    ) throws -> [(x: Double, y: Double, rotation: Double, bedIndex: Int)] {
        guard !meshes.isEmpty else { return [] }

        var sceneObjects: [NSA1SceneObject] = []
        var matrixPointers: [UnsafeMutablePointer<Double>] = []
        defer { for p in matrixPointers { p.deallocate() } }
        for meshData in meshes {
            let mbuf = flatten(meshData.matrix)
            let matrixPtr = UnsafeMutablePointer<Double>.allocate(capacity: 16)
            matrixPtr.initialize(from: mbuf, count: 16)
            matrixPointers.append(matrixPtr)
            sceneObjects.append(NSA1SceneObject(
                vertices: UnsafePointer(meshData.vertices),
                vertex_count: meshData.vertices.count / 3,
                indices: UnsafePointer(meshData.indices),
                index_count: meshData.indices.count,
                matrix16: UnsafePointer(matrixPtr),
                paint_data: nil, paint_data_size: 0,
                layer_height_ranges: nil, layer_height_range_count: 0, cut_group_id: 0
            ))
        }

        var results = [NSA1ArrangeResult](
            repeating: NSA1ArrangeResult(x: 0, y: 0, rotation: 0, bed_index: 0),
            count: sceneObjects.count
        )
        let status = sceneObjects.withUnsafeBufferPointer { objBuf in
            results.withUnsafeMutableBufferPointer { resBuf in
                nsa1_auto_arrange(
                    objBuf.baseAddress,
                    objBuf.count,
                    bedWidth,
                    bedHeight,
                    clearance,
                    resBuf.baseAddress
                )
            }
        }
        guard status == 0 else {
            throw SlicingEngineError.sliceFailed("auto-arrange failed")
        }
        return results.map { (x: $0.x, y: $0.y, rotation: $0.rotation, bedIndex: Int($0.bed_index)) }
    }

    /// Loads the first volume's mesh of the model object at `index` from a
    /// 3MF file, via the real engine's `load_3mf`.
    static func loadThreeMFMesh(atPath path: String, objectIndex index: Int) throws -> LoadedMesh {
        guard let raw = path.withCString({ nsa1_load_3mf_mesh($0, Int64(index)) }) else {
            throw SlicingEngineError.objectIndexOutOfRange(path: path, index: index)
        }
        return convert(raw)
    }

    /// Loads real support-paint annotations saved in a 3MF object's
    /// first volume. The returned bytes are opaque TriangleSelector data
    /// passed into `SupportPaintState.deserialize`; an empty array means
    /// the object is unpainted.
    static func loadThreeMFPaint(atPath path: String, objectIndex index: Int) -> [UInt8] {
        var size: Int = 0
        guard let raw = path.withCString({ nsa1_load_3mf_paint($0, Int64(index), &size) }), size > 0 else {
            return []
        }
        defer { nsa1_paint_data_free(raw) }
        return Array(UnsafeBufferPointer(start: raw, count: size))
    }

    /// Reads the real upstream `ModelObject::cut_id` (P4-007 cut
    /// lineage) saved by `storeThreeMF`'s `cutGroupIDs`. `nil` means the
    /// object at `index` was never cut (or has no `cut_id` set).
    static func loadThreeMFCutGroupID(atPath path: String, objectIndex index: Int) -> UInt64? {
        var hasCutID: Int32 = 0
        let value = path.withCString { nsa1_load_3mf_cut_id($0, Int64(index), &hasCutID) }
        return hasCutID != 0 ? value : nil
    }

    /// Reads the first instance's placement matrix of the model object at
    /// `index` from a 3MF file, via the real engine's `load_3mf`.
    static func threeMFObjectTransform(atPath path: String, objectIndex index: Int) throws -> simd_float4x4 {
        var raw = [Double](repeating: 0, count: 16)
        let result = raw.withUnsafeMutableBufferPointer { buf in
            path.withCString { nsa1_3mf_object_matrix($0, Int64(index), buf.baseAddress) }
        }
        guard result == 0 else { throw SlicingEngineError.objectIndexOutOfRange(path: path, index: index) }
        return raw.withUnsafeBufferPointer(unflatten)
    }

    /// Writes `objects` (each a mesh plus its placement matrix) plus
    /// `configEntries` (resolved A1 profile selection + P3-003 overrides)
    /// to a 3MF project file via the real engine's `store_3mf` — P1-007's
    /// project persistence, reusing the same writer BambuStudio/OrcaSlicer
    /// use, extended (P3-003) to also embed the full resolved config so
    /// profile/override selection survives a save/reload round trip.
    /// `paintData` (P3-005) is positionally aligned with `objects`;
    /// nonempty entries become real `ModelVolume::supported_facets` and
    /// are therefore persisted by the upstream 3MF writer.
    static func storeThreeMF(
        atPath path: String,
        objects: [(mesh: LoadedMesh, transform: simd_float4x4)],
        configEntries: [(key: String, value: String)],
        paintData: [[UInt8]] = [],
        cutGroupIDs: [UInt64?] = []
    ) throws {
        let pending = objects.enumerated().map { index, object in
            PendingSceneObject(
                vertices: object.mesh.vertices, indices: object.mesh.indices,
                matrix16: flatten(object.transform),
                paintData: index < paintData.count ? paintData[index] : [],
                cutGroupID: index < cutGroupIDs.count ? (cutGroupIDs[index] ?? 0) : 0
            )
        }
        let result = withNSA1SceneObjects(pending) { objPtr, objCount in
            withNSA1ConfigEntries(configEntries) { cfgPtr, cfgCount in
                path.withCString { nsa1_store_3mf($0, objPtr, objCount, cfgPtr, cfgCount) }
            }
        }
        guard result == 0 else { throw SlicingEngineError.failedToWrite3MF(path: path) }
    }

    /// Reads back the config embedded by `storeThreeMF` from a 3MF project
    /// file via the real engine's `load_3mf` (P3-003 settings persistence).
    /// Returns an empty array for a project with no embedded config (e.g.
    /// one saved before P3-003).
    static func loadThreeMFConfig(atPath path: String) -> [(key: String, value: String)] {
        var count = 0
        guard let raw = path.withCString({ cpath in nsa1_load_3mf_config(cpath, &count) }) else {
            return []
        }
        defer { nsa1_free_config_entries(raw, count) }
        return (0..<count).map { i in
            let entry = raw[i]
            return (String(cString: entry.key), String(cString: entry.value))
        }
    }

    /// Slices `objects` (mesh + placement matrix) with `configEntries` (A1
    /// profile fields resolved by `SlicingJob`) and writes real G-code to
    /// `outputPath` via the real engine's `Print::apply`/`validate`/
    /// `process`/`export_gcode` pipeline (P1-008). Returns the real
    /// per-move toolpath the engine computed while writing that G-code
    /// (P1-009), for viewport preview. `paintData[i]` (P3-005, from
    /// `SupportPaintState.serialize()`) is each object's real
    /// enforcer/blocker support-paint state, positionally aligned with
    /// `objects`; an empty array or a shorter `paintData` than `objects`
    /// means that object is unpainted.
    @discardableResult
    static func sliceToGCode(
        objects: [(mesh: LoadedMesh, transform: simd_float4x4)],
        configEntries: [(key: String, value: String)],
        outputPath: String,
        paintData: [[UInt8]] = [],
        layerHeightRanges: [[LayerHeightRange]] = []
    ) throws -> [ToolpathSegment] {
        let pendingObjects = objects.enumerated().map { index, object in
            PendingSceneObject(
                vertices: object.mesh.vertices, indices: object.mesh.indices,
                matrix16: flatten(object.transform),
                paintData: index < paintData.count ? paintData[index] : [],
                layerHeightRanges: (index < layerHeightRanges.count ? layerHeightRanges[index] : [])
                    .map { NSA1LayerHeightRange(z_min: $0.zMin, z_max: $0.zMax, layer_height: $0.layerHeight) }
            )
        }
        var errorMessage: String?
        var toolpath: [ToolpathSegment] = []
        let result = withNSA1SceneObjects(pendingObjects) { objPtr, objCount in
            withNSA1ConfigEntries(configEntries) { cfgPtr, cfgCount in
                outputPath.withCString { outPtr -> Int32 in
                    var errPtr: UnsafeMutablePointer<CChar>?
                    var toolpathPtr: UnsafeMutablePointer<NSA1Toolpath>?
                    let r = nsa1_slice_to_gcode(objPtr, objCount, cfgPtr, cfgCount, outPtr, &toolpathPtr, &errPtr)
                    if let errPtr {
                        errorMessage = String(cString: errPtr)
                        nsa1_free_string(errPtr)
                    }
                    if let toolpathPtr {
                        defer { nsa1_free_toolpath(toolpathPtr) }
                        let segs = UnsafeBufferPointer(start: toolpathPtr.pointee.segments, count: toolpathPtr.pointee.segment_count)
                        toolpath = segs.map {
                                                                ToolpathSegment(
                                        start: SIMD3($0.start_x, $0.start_y, $0.start_z),
                                        end: SIMD3($0.end_x, $0.end_y, $0.end_z),
                                        width: $0.width,
                                        height: $0.height,
                                        isTravel: $0.is_travel != 0,
                                        feedrate: $0.feedrate,
                                        temperature: $0.temperature,
                                        layerDuration: $0.layer_duration,
                                        extruderID: Int32($0.extruder_id),
                                        extrusionRole: $0.extrusion_role,
                                    )
                        }
                    }
                    return r
                }
            }
        }
        guard result == 0 else {
            throw SlicingEngineError.sliceFailed(errorMessage ?? "unknown engine error")
        }
        return toolpath
    }

    /// Slice output with estimated print statistics (P1-011).
    struct EstimatedPrintStatistics: Sendable {
        let normalTime: Double
        let normalPrepareTime: Double
        let stealthTime: Double
        let stealthPrepareTime: Double
        let totalFilamentLoadTime: Double
        let totalFilamentUnloadTime: Double
        let totalToolChangeTime: Double
        let totalTravelDistance: Double
        let totalFilamentChanges: Int
        let totalFlushFilamentChanges: Int
        let totalExtruderChanges: Int
        let totalTravelMoves: Int
        let totalSeamGapDistance: Double
        let totalSeamScarfDistance: Double
        let extruderVolumesMM3: [Double]
        let roleLengthsMM: [Double]
        let roleVolumesMM3: [Double]
    }

    @discardableResult
    static func sliceToGCodeWithStatistics(
        objects: [(mesh: LoadedMesh, transform: simd_float4x4)],
        configEntries: [(key: String, value: String)],
        outputPath: String
    ) throws -> (toolpath: [ToolpathSegment], statistics: EstimatedPrintStatistics) {
        let pendingObjects = objects.map {
            PendingSceneObject(vertices: $0.mesh.vertices, indices: $0.mesh.indices, matrix16: flatten($0.transform))
        }
        var errorMessage: String?
        var toolpath: [ToolpathSegment] = []
        var stats: EstimatedPrintStatistics?
        let result = withNSA1SceneObjects(pendingObjects) { objPtr, objCount in
            withNSA1ConfigEntries(configEntries) { cfgPtr, cfgCount in
                outputPath.withCString { outPtr -> Int32 in
                    var errPtr: UnsafeMutablePointer<CChar>?
                    var toolpathPtr: UnsafeMutablePointer<NSA1Toolpath>?
                    var statsPtr: UnsafeMutablePointer<NSA1EstimatedStatistics>?
                    let r = nsa1_slice_to_gcode_with_statistics(
                        objPtr, objCount, cfgPtr, cfgCount, outPtr,
                        &toolpathPtr, &statsPtr, &errPtr
                    )
                    if let errPtr {
                        errorMessage = String(cString: errPtr)
                        nsa1_free_string(errPtr)
                    }
                    if let toolpathPtr {
                        defer { nsa1_free_toolpath(toolpathPtr) }
                        let segs = UnsafeBufferPointer(start: toolpathPtr.pointee.segments, count: toolpathPtr.pointee.segment_count)
                        toolpath = segs.map {
                                                                ToolpathSegment(
                                        start: SIMD3($0.start_x, $0.start_y, $0.start_z),
                                        end: SIMD3($0.end_x, $0.end_y, $0.end_z),
                                        width: $0.width,
                                        height: $0.height,
                                        isTravel: $0.is_travel != 0,
                                        feedrate: $0.feedrate,
                                        temperature: $0.temperature,
                                        layerDuration: $0.layer_duration,
                                        extruderID: Int32($0.extruder_id),
                                        extrusionRole: $0.extrusion_role,
                                    )
                        }
                    }
                    if let statsPtr {
                        defer { nsa1_free_estimated_statistics(statsPtr) }
                        let s = statsPtr.pointee
                        stats = EstimatedPrintStatistics(
                            normalTime: s.normal_time,
                            normalPrepareTime: s.normal_prepare_time,
                            stealthTime: s.stealth_time,
                            stealthPrepareTime: s.stealth_prepare_time,
                            totalFilamentLoadTime: s.total_filament_load_time,
                            totalFilamentUnloadTime: s.total_filament_unload_time,
                            totalToolChangeTime: s.total_tool_change_time,
                            totalTravelDistance: s.total_travel_distance,
                            totalFilamentChanges: Int(s.total_filament_changes),
                            totalFlushFilamentChanges: Int(s.total_flush_filament_changes),
                            totalExtruderChanges: Int(s.total_extruder_changes),
                            totalTravelMoves: Int(s.total_travel_moves),
                            totalSeamGapDistance: s.total_seam_gap_distance,
                            totalSeamScarfDistance: s.total_seam_scarf_distance,
                            extruderVolumesMM3: UnsafeBufferPointer(start: s.extruder_volumes_mm3, count: Int(s.extruder_count)).map { $0 },
                            roleLengthsMM: UnsafeBufferPointer(start: s.role_lengths_mm, count: Int(s.role_count)).map { $0 },
                            roleVolumesMM3: UnsafeBufferPointer(start: s.role_volumes_mm3, count: Int(s.role_count)).map { $0 }
                        )
                    }
                    return r
                }
            }
        }
        guard result == 0 else {
            throw SlicingEngineError.sliceFailed(errorMessage ?? "unknown engine error")
        }
        return (toolpath, stats!)
    }

    /// Calls the dedicated calibration C ABI. Generation remains entirely
    /// local: no printer connection, upload, or start-print operation is
    /// available through this API.
    static func generateCalibrationGCode(
        request: CalibrationRequest,
        resourceURL: URL,
        configEntries: [(key: String, value: String)],
        outputPath: String
    ) throws -> CalibrationGeneration {
        var errorMessage: String?
        var generation = CalibrationGeneration(toolpath: [], blocks: [], outputPath: outputPath)
        let result = withNSA1ConfigEntries(configEntries) { cfgPtr, cfgCount in
            resourceURL.path.withCString { resourcePtr in
                outputPath.withCString { outputPtr -> Int32 in
                    var rawResult: UnsafeMutablePointer<NSA1CalibrationResult>?
                    var rawError: UnsafeMutablePointer<CChar>?
                    var rawRequest = NSA1CalibrationRequest(
                        workflow: request.workflow.bridgeValue,
                        start: request.start,
                        end: request.end,
                        step: request.step,
                        resource_path: resourcePtr,
                        config_entries: cfgPtr,
                        config_entry_count: cfgCount
                    )
                    let status = nsa1_generate_calibration_gcode(
                        &rawRequest,
                        outputPtr,
                        &rawResult,
                        &rawError
                    )
                    if let rawError {
                        errorMessage = String(cString: rawError)
                        nsa1_free_string(rawError)
                    }
                    if let rawResult {
                        defer { nsa1_free_calibration_result(rawResult) }
                        if let toolpath = rawResult.pointee.toolpath {
                            let segments = UnsafeBufferPointer(
                                start: toolpath.pointee.segments,
                                count: toolpath.pointee.segment_count
                            )
                            generation = CalibrationGeneration(
                                toolpath: segments.map {
                                                                        ToolpathSegment(
                                        start: SIMD3($0.start_x, $0.start_y, $0.start_z),
                                        end: SIMD3($0.end_x, $0.end_y, $0.end_z),
                                        width: $0.width,
                                        height: $0.height,
                                        isTravel: $0.is_travel != 0,
                                        feedrate: $0.feedrate,
                                        temperature: $0.temperature,
                                        layerDuration: $0.layer_duration,
                                        extruderID: Int32($0.extruder_id),
                                        extrusionRole: $0.extrusion_role,
                                    )
                                },
                                blocks: rawResult.pointee.blocks.map {
                                    UnsafeBufferPointer(
                                        start: $0,
                                        count: rawResult.pointee.block_count
                                    ).map {
                                        CalibrationBlock(
                                            ordinal: Int($0.ordinal),
                                            value: $0.value,
                                            startZ: $0.start_z,
                                            endZ: $0.end_z
                                        )
                                    }
                                } ?? [],
                                outputPath: outputPath
                            )
                        }
                    }
                    return status
                }
            }
        }
        guard result == 0 else {
            throw SlicingEngineError.sliceFailed(errorMessage ?? "unknown calibration error")
        }
        return generation
    }

    /// Cuts a model object along a user-specified world-space plane
    /// (P4-004). `objects` is normally exactly one `(mesh, transform)`
    /// pair — the real engine's `ModelObject::cut` only ever cuts
    /// `model.objects.front()`. `planePoints` are 4 points in the SAME
    /// world space as `transform`'s translation (upstream's `cut()`
    /// subtracts the instance offset from these points internally, so
    /// they must already be where the object is actually placed, not
    /// mesh-local coordinates). Returns the resulting parts (0, 1, or 2
    /// depending on `cutMode`) each as a real `(mesh, transform)` pair —
    /// the transform is the real engine's own post-cut instance
    /// placement (`reset_instance_transformation`), which is NOT always
    /// identity (e.g. an object cut away from the world origin keeps
    /// that world offset) and must not be dropped.
    static func cutModel(
        objects: [(mesh: LoadedMesh, transform: simd_float4x4)],
        planePoints: [(Float, Float, Float)],
        cutMode: CutMode,
        connectors: [(position: SIMD3<Float>, normal: SIMD3<Float>, preset: ConnectorPreset)] = []
    ) throws -> [(mesh: LoadedMesh, transform: simd_float4x4)] {
        guard planePoints.count == 4 else {
            throw SlicingEngineError.sliceFailed("cut plane requires exactly 4 points")
        }

        var errorMessage: String?
        var cutRequest = NSA1CutRequest(
            plane_points: (
                NSA1Vec3d(x: Double(planePoints[0].0), y: Double(planePoints[0].1), z: Double(planePoints[0].2)),
                NSA1Vec3d(x: Double(planePoints[1].0), y: Double(planePoints[1].1), z: Double(planePoints[1].2)),
                NSA1Vec3d(x: Double(planePoints[2].0), y: Double(planePoints[2].1), z: Double(planePoints[2].2)),
                NSA1Vec3d(x: Double(planePoints[3].0), y: Double(planePoints[3].1), z: Double(planePoints[3].2))
            ),
            cut_mode: cutMode.rawValue,
            connectors: nil,
            connector_count: 0
        )
        let rawConnectors = connectors.map { connector in
            NSA1CutConnector(
                position: NSA1Vec3d(x: Double(connector.position.x), y: Double(connector.position.y), z: Double(connector.position.z)),
                normal: NSA1Vec3d(x: Double(connector.normal.x), y: Double(connector.normal.y), z: Double(connector.normal.z)),
                type: connector.preset.type.rawValue,
                style: connector.preset.style.rawValue,
                shape: connector.preset.shape.rawValue,
                radius: connector.preset.radius,
                height: connector.preset.height,
                radius_tolerance: connector.preset.radiusTolerance,
                height_tolerance: connector.preset.heightTolerance
            )
        }

        let pending = objects.map { object in
            PendingSceneObject(
                vertices: object.mesh.vertices, indices: object.mesh.indices,
                matrix16: flatten(object.transform)
            )
        }

        var rawResultPtr: UnsafeMutablePointer<UnsafeMutablePointer<NSA1SceneObject>?>? = nil
        var resultCount: Int = 0
        var rawError: UnsafeMutablePointer<CChar>? = nil

        let status = rawConnectors.withUnsafeBufferPointer { connectorBuffer in
            cutRequest.connectors = connectorBuffer.baseAddress
            cutRequest.connector_count = connectorBuffer.count
            return withNSA1SceneObjects(pending) { objPtr, objCount in
                nsa1_cut_model(objPtr, objCount, &cutRequest, &rawResultPtr, &resultCount, &rawError)
            }
        }

        if let rawError {
            errorMessage = String(cString: rawError)
            nsa1_free_string(rawError)
        }

        guard status == 0 else {
            throw SlicingEngineError.sliceFailed(errorMessage ?? "unknown cut error")
        }

        guard resultCount > 0, let rawResultPtr else {
            return []
        }

        let resultPtrs = UnsafeBufferPointer(start: rawResultPtr, count: resultCount)
        var results: [(mesh: LoadedMesh, transform: simd_float4x4)] = []
        results.reserveCapacity(resultCount)
        for ptr in resultPtrs {
            let sceneObj = ptr!.pointee
            let vertices = Array(UnsafeBufferPointer(start: sceneObj.vertices, count: Int(sceneObj.vertex_count) * 3))
            let indices = Array(UnsafeBufferPointer(start: sceneObj.indices, count: Int(sceneObj.index_count)))
            let transform: simd_float4x4
            if let matrix16 = sceneObj.matrix16 {
                transform = unflatten(UnsafeBufferPointer(start: matrix16, count: 16))
            } else {
                transform = matrix_identity_float4x4
            }
            results.append((mesh: LoadedMesh(vertices: vertices, indices: indices), transform: transform))
        }

        nsa1_free_cut_results(rawResultPtr, resultCount)
        return results
    }

}
