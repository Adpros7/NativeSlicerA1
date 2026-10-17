import XCTest
@testable import NativeSlicerA1

final class BuildPlateGeometryTests: XCTestCase {
    func testRealA1DimensionsProduceExpectedSegmentCounts() {
        let segments = BuildPlateGeometry.segments()
        // 4 outline edges + 25 vertical + 25 horizontal grid lines (10mm
        // spacing, 0..<256) + 3 axis indicators.
        XCTAssertEqual(segments.count, 4 + 25 + 25 + 3)
    }

    func testOutlineMatchesRealA1BedCorners() {
        let segments = BuildPlateGeometry.segments()
        let outline = segments.prefix(4)
        XCTAssertEqual(outline[0].start, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(outline[1].start, SIMD3<Float>(256, 0, 0))
        XCTAssertEqual(outline[2].start, SIMD3<Float>(256, 256, 0))
        XCTAssertEqual(outline[3].start, SIMD3<Float>(0, 256, 0))
        XCTAssertTrue(outline.allSatisfy { $0.color == BuildPlateGeometry.plateColor })
    }

    func testGridStaysWithinBedBounds() {
        let segments = BuildPlateGeometry.segments()
        let gridLines = segments.filter { $0.color == BuildPlateGeometry.gridColor }
        XCTAssertTrue(gridLines.allSatisfy { $0.start.x >= 0 && $0.start.x <= 256 && $0.start.y >= 0 && $0.start.y <= 256 })
    }

    func testAxesOriginateAtBedOriginWithDistinctColors() {
        let segments = BuildPlateGeometry.segments()
        let axes = segments.suffix(3)
        XCTAssertTrue(axes.allSatisfy { $0.start == .zero })
        XCTAssertEqual(Set(axes.map(\.color)).count, 3, "each axis must be a distinct color")
    }
}
