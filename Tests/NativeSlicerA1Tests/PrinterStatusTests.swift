import XCTest
@testable import NativeSlicerA1

final class PrintStatusReportTests: XCTestCase {
    func testParsesRealReportShapeFromResearchDoc() throws {
        let report: [String: Any] = [
            "print": [
                "nozzle_temper": 23.625,
                "nozzle_target_temper": 0,
                "bed_temper": 20.71875,
                "bed_target_temper": 0,
                "chamber_temper": 5,
                "gcode_state": "RUNNING",
                "mc_percent": 45,
                "mc_remaining_time": 3600,
                "layer_num": 125,
                "total_layer_num": 250,
                "print_error": 0,
                "wifi_signal": -40,
            ]
        ]
        let status = try XCTUnwrap(PrintStatusReport(report: report))
        XCTAssertEqual(status.nozzleTemperature, 23.625)
        XCTAssertEqual(status.bedTemperature, 20.71875)
        XCTAssertEqual(status.gcodeState, .running)
        XCTAssertEqual(status.percentComplete, 45)
        XCTAssertEqual(status.remainingTimeMinutes, 3600)
        XCTAssertEqual(status.currentLayer, 125)
        XCTAssertEqual(status.totalLayers, 250)
        XCTAssertEqual(status.printError, 0)
        XCTAssertEqual(status.wifiSignalDBM, -40)
    }

    func testMissingPrintKeyReturnsNil() {
        XCTAssertNil(PrintStatusReport(report: ["system": ["foo": "bar"]]))
    }

    func testUnknownGCodeStateKeepsRawStringWithoutCrashing() throws {
        let status = try XCTUnwrap(PrintStatusReport(report: ["print": ["gcode_state": "SOME_NEW_STATE"]]))
        XCTAssertNil(status.gcodeState)
        XCTAssertEqual(status.rawGCodeState, "SOME_NEW_STATE")
    }

    func testStringEncodedNumbersAreAccepted() throws {
        let status = try XCTUnwrap(PrintStatusReport(report: ["print": ["mc_percent": "72", "wifi_signal": "-55"]]))
        XCTAssertEqual(status.percentComplete, 72)
        XCTAssertEqual(status.wifiSignalDBM, -55)
    }
}

final class PrinterConnectionCommandTests: XCTestCase {
    func testPausePublishesRealPauseCommand() throws {
        let recorder = RecordingConnection()
        try recorder.pausePrint()
        XCTAssertEqual(recorder.published?["print"] as? [String: String], ["command": "pause", "sequence_id": "1"])
    }

    func testResumePublishesRealResumeCommand() throws {
        let recorder = RecordingConnection()
        try recorder.resumePrint()
        XCTAssertEqual((recorder.published?["print"] as? [String: String])?["command"], "resume")
    }

    func testStopPublishesRealStopCommand() throws {
        let recorder = RecordingConnection()
        try recorder.stopPrint()
        XCTAssertEqual((recorder.published?["print"] as? [String: String])?["command"], "stop")
    }

    func testStartPrintBuildsRealProjectFileCommand() throws {
        let recorder = RecordingConnection()
        try recorder.startPrint(fileName: "plate_1.gcode.3mf", useAMS: true)
        let payload = try XCTUnwrap(recorder.published?["print"] as? [String: Any])
        XCTAssertEqual(payload["command"] as? String, "project_file")
        XCTAssertEqual(payload["url"] as? String, "file:///sdcard/bbl_plater/plate_1.gcode.3mf")
        XCTAssertEqual(payload["use_ams"] as? Bool, true)
    }
}

/// Subclassing `PrinterConnection` to intercept `send(_:)` without a real
/// MQTT connection — the extension methods under test (`pausePrint()`
/// etc.) only build a payload and call `send`, so overriding `send` is
/// sufficient to observe the real payload they construct.
private final class RecordingConnection: PrinterConnection {
    var published: [String: Any]?
    init() { super.init(host: "127.0.0.1", serial: "test", accessCode: "unused") }
    override func send(_ payload: [String: Any]) throws { published = payload }
}
