import XCTest
@testable import NativeSlicerA1

/// Proves Swift calls through to the real, vendored libslic3r engine
/// (not a mock/stub) by parsing a real STL file and checking its actual
/// triangle count.
final class SlicingEngineBridgeTests: XCTestCase {
    func testParsesRealSTLViaRealEngine() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent() // Tests/NativeSlicerA1Tests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let url = repoRoot.appendingPathComponent("Sources/NativeSlicerA1/Resources/Profiles/BBL/bbl-3dp-X1.stl")
        let count = try SlicingEngine.stlTriangleCount(atPath: url.path)
        XCTAssertEqual(count, 1016)
    }

    func testMissingFileThrows() {
        XCTAssertThrowsError(try SlicingEngine.stlTriangleCount(atPath: "/nonexistent/path.stl"))
    }
}
