import XCTest
@testable import NativeSlicerA1

final class AMSLiteTests: XCTestCase {
    func testParsesUnitReportAndOccupancyBitmask() throws {
        // "e" = 0b1110 -> slots 1, 2, 3 occupied, slot 0 empty.
        let unit: [String: Any] = [
            "id": 0,
            "tray": [
                ["id": 1, "tray_color": "FF0000FF", "tray_type": "PLA", "remain": 80],
                ["id": 2, "tray_color": "00FF00FF", "tray_type": "PETG", "remain": 45],
                ["id": 3, "tray_color": "0000FFFF", "tray_type": "ABS", "remain": 10],
            ],
        ]
        let state = try XCTUnwrap(AMSLiteState(unit: unit, trayExistBitsHex: "e", trayNow: "2"))

        XCTAssertEqual(state.unitID, 0)
        XCTAssertEqual(state.slots.count, 4)
        XCTAssertEqual(state.slots[0].occupied, false)
        XCTAssertEqual(state.slots[1].occupied, true)
        XCTAssertEqual(state.slots[1].filamentType, "PLA")
        XCTAssertEqual(state.slots[2].remainPercent, 45)
        XCTAssertEqual(state.activeTray, 2)
    }

    func testExternalSpoolTrayNowIsNilActiveTray() throws {
        let unit: [String: Any] = ["id": 0, "tray": []]
        let state = try XCTUnwrap(AMSLiteState(unit: unit, trayExistBitsHex: "0", trayNow: "255"))
        XCTAssertNil(state.activeTray)
    }

    func testMappingMatchesResearchExamples() {
        // Table from RESEARCH-P0-008.md §5.
        XCTAssertEqual(AMSMapping.build(slotsByColorIndex: [0]), [-1, -1, -1, -1, 0])
        XCTAssertEqual(AMSMapping.build(slotsByColorIndex: [1, 0]), [-1, -1, -1, 1, 0])
        XCTAssertEqual(AMSMapping.build(slotsByColorIndex: [2, 1, 0]), [-1, -1, 2, 1, 0])
        XCTAssertEqual(AMSMapping.build(slotsByColorIndex: [3, 2, 1, 0]), [-1, 3, 2, 1, 0])
    }
}
