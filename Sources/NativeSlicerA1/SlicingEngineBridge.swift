import CSlic3rBridge
import Foundation

enum SlicingEngineError: Error {
    case failedToReadSTL(path: String)
}

/// A real-geometry mesh loaded through the engine bridge: flat vertex (XYZ
/// triples) and triangle index buffers, ready to upload to a Metal vertex
/// buffer.
struct LoadedMesh {
    let vertices: [Float] // XYZ triples
    let indices: [UInt32] // 3 per triangle
    var triangleCount: Int { indices.count / 3 }
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
        defer { nsa1_free_mesh(raw) }

        let vertexFloatCount = raw.pointee.vertex_count * 3
        let vertices = Array(UnsafeBufferPointer(start: raw.pointee.vertices, count: vertexFloatCount))
        let indices = Array(UnsafeBufferPointer(start: raw.pointee.indices, count: raw.pointee.index_count))
        return LoadedMesh(vertices: vertices, indices: indices)
    }
}
