import XCTest
@testable import NativeSlicerA1

final class CalibrationJobTests: XCTestCase {
    func testBundledCalibrationResourcesExist() throws {
        for name in [
            "flowrate-test-pass1",
            "flowrate-test-pass2",
            "temperature_tower",
            "retraction_tower",
            "SpeedTestStructure",
        ] {
            XCTAssertNotNil(CalibrationResources.url(named: name), "missing bundled calibration resource \(name)")
        }
    }
}
