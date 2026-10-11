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

    func testFlowRateRejectsNonPositiveStep() throws {
        let request = CalibrationRequest(
            workflow: .flowRate,
            start: 0.95,
            end: 1.05,
            step: 0,
            selection: .init()
        )

        XCTAssertThrowsError(try CalibrationJob.validate(
            request,
            loader: try BambuProfileLoader(),
            capabilities: .all
        )) { error in
            XCTAssertEqual(
                error as? CalibrationError,
                .invalidRange(start: 0.95, end: 1.05, step: 0)
            )
        }
    }

    func testPressureAdvanceRequiresExplicitCapability() throws {
        let request = CalibrationRequest(
            workflow: .pressureAdvance,
            start: 0,
            end: 0.02,
            step: 0.002,
            selection: .init()
        )

        XCTAssertThrowsError(try CalibrationJob.validate(
            request,
            loader: try BambuProfileLoader(),
            capabilities: []
        )) { error in
            XCTAssertEqual(
                error as? CalibrationError,
                .unsupportedCapability(.pressureAdvance)
            )
        }
    }

    func testCalibrationValidatesProfileBeforeCapability() throws {
        var selection = SlicingJob.ProfileSelection()
        selection.process = "missing profile"
        let request = CalibrationRequest(
            workflow: .temperature,
            start: 230,
            end: 220,
            step: 5,
            selection: selection
        )

        XCTAssertThrowsError(try CalibrationJob.validate(
            request,
            loader: try BambuProfileLoader(),
            capabilities: []
        )) { error in
            XCTAssertTrue(error is BambuProfileError)
        }
    }
}
