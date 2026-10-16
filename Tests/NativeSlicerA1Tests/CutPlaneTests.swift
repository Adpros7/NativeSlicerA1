import XCTest
import simd
@testable import NativeSlicerA1

final class CutPlaneTests: XCTestCase {
    /// P4-006: a generated connector's local +Z axis must align with the
    /// active cut plane normal, and its z=height/2 midpoint must sit on
    /// the clicked plane point. This is the real transform used both for
    /// Metal preview placement and for the C-ABI connector input.
    func testConnectorTransformCentersAndAlignsConnectorOnPlane() {
        let plane = CutPlane(center: SIMD3(10, 20, 30), tiltX: .pi / 2, halfExtent: 50)
        let preset = ConnectorPreset(radius: 5, height: 10)
        let transform = plane.connectorTransform(at: SIMD3(4, 5, 6), preset: preset)

        let midpoint = transform * SIMD4<Float>(0, 0, 5, 1)
        XCTAssertEqual(SIMD3(midpoint.x, midpoint.y, midpoint.z), SIMD3(4, 5, 6), accuracy: 0.001)

        let transformedAxis = transform * SIMD4<Float>(0, 0, 1, 0)
        XCTAssertEqual(
            normalize(SIMD3(transformedAxis.x, transformedAxis.y, transformedAxis.z)),
            plane.normal,
            accuracy: 0.001
        )
    }
}

private func XCTAssertEqual(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, accuracy: Float, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, file: file, line: line)
}
