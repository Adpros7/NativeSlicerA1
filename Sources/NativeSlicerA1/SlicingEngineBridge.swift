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
struct ToolpathSegment {
    let start: SIMD3<Float>
    let end: SIMD3<Float>
    let width: Float
    let height: Float
    let isTravel: Bool
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

private struct PendingSceneObject {
    let vertices: [Float]
    let indices: [UInt32]
    let matrix16: [Double]
}

/// Recursively pins each object's vertex/index/matrix arrays with nested
/// `withUnsafeBufferPointer` scopes so the flat `NSA1SceneObject` array
/// handed to `body` stays valid for the whole call — the C function never
/// outlives this stack frame, so no manual lifetime management is needed.
private func withNSA1SceneObjects<R>(_ pending: [PendingSceneObject], _ body: (UnsafePointer<NSA1SceneObject>?, Int) -> R) -> R {
    func build(_ index: Int, _ acc: inout [NSA1SceneObject]) -> R {
        guard index < pending.count else {
            return acc.withUnsafeBufferPointer { body($0.baseAddress, acc.count) }
        }
        let object = pending[index]
        return object.vertices.withUnsafeBufferPointer { vbuf in
            object.indices.withUnsafeBufferPointer { ibuf in
                object.matrix16.withUnsafeBufferPointer { mbuf in
                    acc.append(NSA1SceneObject(vertices: vbuf.baseAddress, vertex_count: vbuf.count / 3, indices: ibuf.baseAddress, index_count: ibuf.count, matrix16: mbuf.baseAddress))
                    return build(index + 1, &acc)
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

    /// Loads the first volume's mesh of the model object at `index` from a
    /// 3MF file, via the real engine's `load_3mf`.
    static func loadThreeMFMesh(atPath path: String, objectIndex index: Int) throws -> LoadedMesh {
        guard let raw = path.withCString({ nsa1_load_3mf_mesh($0, Int64(index)) }) else {
            throw SlicingEngineError.objectIndexOutOfRange(path: path, index: index)
        }
        return convert(raw)
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
    static func storeThreeMF(atPath path: String, objects: [(mesh: LoadedMesh, transform: simd_float4x4)], configEntries: [(key: String, value: String)]) throws {
        let pending = objects.map {
            PendingSceneObject(vertices: $0.mesh.vertices, indices: $0.mesh.indices, matrix16: flatten($0.transform))
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
    /// (P1-009), for viewport preview.
    @discardableResult
    static func sliceToGCode(
        objects: [(mesh: LoadedMesh, transform: simd_float4x4)],
        configEntries: [(key: String, value: String)],
        outputPath: String
    ) throws -> [ToolpathSegment] {
        let pendingObjects = objects.map {
            PendingSceneObject(vertices: $0.mesh.vertices, indices: $0.mesh.indices, matrix16: flatten($0.transform))
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
                                isTravel: $0.is_travel != 0
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
                                        isTravel: $0.is_travel != 0
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
}
