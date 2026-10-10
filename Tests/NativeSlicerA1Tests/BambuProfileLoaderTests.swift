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

    func testUnknownProfileThrows() throws {
        let loader = try BambuProfileLoader()
        XCTAssertThrowsError(try loader.resolve("does not exist")) { error in
            XCTAssertEqual(error as? BambuProfileError, .profileNotFound("does not exist"))
        }
    }
}
