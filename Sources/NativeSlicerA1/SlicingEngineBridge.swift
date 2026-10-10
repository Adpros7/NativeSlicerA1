import CSlic3rBridge
import Foundation

enum SlicingEngineError: Error {
    case failedToReadSTL(path: String)
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
}
