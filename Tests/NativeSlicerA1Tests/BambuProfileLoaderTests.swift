import XCTest
@testable import NativeSlicerA1

final class BambuProfileLoaderTests: XCTestCase {
    func testLoadsVendoredA1Profiles() throws {
        let loader = try BambuProfileLoader()
        XCTAssertNotNil(loader.profile(named: "Bambu Lab A1 0.4 nozzle"))
        XCTAssertNotNil(loader.profile(named: "fdm_machine_common"))
    }

    /// `best_object_pos` is only defined on the root `fdm_machine_common`
    /// ancestor, three inheritance hops above the A1 0.4 nozzle profile.
    /// Resolving it proves the merge walks the whole chain, not just the
    /// immediate parent.
    func testResolvesMultiLevelInheritance() throws {
        let loader = try BambuProfileLoader()
        let resolved = try loader.resolve("Bambu Lab A1 0.4 nozzle")

        XCTAssertEqual(resolved["best_object_pos"] as? String, "0.5x0.5")
        // Overridden at the leaf, must win over any ancestor value.
        XCTAssertEqual(resolved["printable_height"] as? String, "256")
        XCTAssertEqual(resolved["printer_model"] as? String, "Bambu Lab A1")
    }

    /// Per-nozzle custom G-code templates (P1-008/P3-003 known gap,
    /// ARCHITECTURE.md): the A1 0.4 nozzle machine profile's `include`
    /// list names 5 template fragment profiles (e.g. `Bambu Lab A1 0.4
    /// nozzle template machine_start_gcode`) carrying the real A1-specific
    /// `machine_start_gcode` — distinct from (and overriding) the generic
    /// placeholder on the `fdm_machine_common` ancestor it inherits from.
    /// `M9833.2` is a line unique to the A1-specific template, not present
    /// in the generic ancestor's gcode.
    func testResolvesIncludedGCodeTemplates() throws {
        let loader = try BambuProfileLoader()
        let resolved = try loader.resolve("Bambu Lab A1 0.4 nozzle")

        let genericStartGCode = try loader.resolve("fdm_machine_common")["machine_start_gcode"] as? String
        XCTAssertNotNil(genericStartGCode)
        XCTAssertFalse(genericStartGCode!.contains("M9833.2"))

        let startGCode = resolved["machine_start_gcode"] as? String
        XCTAssertNotNil(startGCode)
        XCTAssertTrue(startGCode!.contains("M9833.2"), "expected the A1-specific included start G-code template, not the generic ancestor's")
        XCTAssertNotEqual(startGCode, genericStartGCode)
    }

    func testUnknownProfileThrows() throws {
        let loader = try BambuProfileLoader()
        XCTAssertThrowsError(try loader.resolve("does not exist")) { error in
            XCTAssertEqual(error as? BambuProfileError, .profileNotFound("does not exist"))
        }
    }
}
