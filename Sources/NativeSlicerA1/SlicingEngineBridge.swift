import CSlic3rBridge
import Foundation
import simd

enum SlicingEngineError: Error {
    case failedToReadSTL(path: String)
    case failedToRead3MF(path: String)
    case failedToWrite3MF(path: String)
    case objectIndexOutOfRange(path: String, index: Int)
    case unsupportedFileType(String)
    case sliceFailed(String)
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

    /// Writes `objects` (each a mesh plus its placement matrix) to a 3MF
    /// project file via the real engine's `store_3mf` — P1-007's project
    /// persistence, reusing the same writer BambuStudio/OrcaSlicer use.
    static func storeThreeMF(atPath path: String, objects: [(mesh: LoadedMesh, transform: simd_float4x4)]) throws {
        let pending = objects.map {
            PendingSceneObject(vertices: $0.mesh.vertices, indices: $0.mesh.indices, matrix16: flatten($0.transform))
        }
        let result = withNSA1SceneObjects(pending) { ptr, count in
            path.withCString { nsa1_store_3mf($0, ptr, count) }
        }
        guard result == 0 else { throw SlicingEngineError.failedToWrite3MF(path: path) }
    }

    /// Slices `objects` (mesh + placement matrix) with `configEntries` (A1
    /// profile fields resolved by `SlicingJob`) and writes real G-code to
    /// `outputPath` via the real engine's `Print::apply`/`validate`/
    /// `process`/`export_gcode` pipeline (P1-008).
    static func sliceToGCode(
        objects: [(mesh: LoadedMesh, transform: simd_float4x4)],
        configEntries: [(key: String, value: String)],
        outputPath: String
    ) throws {
        let pendingObjects = objects.map {
            PendingSceneObject(vertices: $0.mesh.vertices, indices: $0.mesh.indices, matrix16: flatten($0.transform))
        }
        var errorMessage: String?
        let result = withNSA1SceneObjects(pendingObjects) { objPtr, objCount in
            withNSA1ConfigEntries(configEntries) { cfgPtr, cfgCount in
                outputPath.withCString { outPtr -> Int32 in
                    var errPtr: UnsafeMutablePointer<CChar>?
                    let r = nsa1_slice_to_gcode(objPtr, objCount, cfgPtr, cfgCount, outPtr, &errPtr)
                    if let errPtr {
                        errorMessage = String(cString: errPtr)
                        nsa1_free_string(errPtr)
                    }
                    return r
                }
            }
        }
        guard result == 0 else {
            throw SlicingEngineError.sliceFailed(errorMessage ?? "unknown engine error")
        }
    }
}
