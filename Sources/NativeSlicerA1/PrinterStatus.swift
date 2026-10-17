import Foundation

/// Structured decode of a real `device/{serial}/report` MQTT payload
/// (RESEARCH-P0-007.md §"Message Formats"/"Status Report") into typed
/// fields the Device UI reads directly — replaces reading the raw
/// `[String: Any]` dictionary field-by-field in view code. Every field is
/// optional: the printer omits fields it has nothing to report, and this
/// type never fabricates a default for a field it didn't see.
struct PrintStatusReport: Equatable {
    enum GCodeState: String {
        case idle = "IDLE"
        case running = "RUNNING"
        case pause = "PAUSE"
        case failed = "FAILED"
        case finish = "FINISH"
    }

    let nozzleTemperature: Double?
    let nozzleTargetTemperature: Double?
    let bedTemperature: Double?
    let bedTargetTemperature: Double?
    let chamberTemperature: Double?
    let gcodeState: GCodeState?
    /// Raw `gcode_state` string when it doesn't match a known
    /// `GCodeState` case (printer firmware adds states over time) — kept
    /// so the UI can still show *something* instead of silently dropping
    /// an unrecognized real value.
    let rawGCodeState: String?
    let percentComplete: Int?
    let remainingTimeMinutes: Int?
    let currentLayer: Int?
    let totalLayers: Int?
    let printError: Int?
    let wifiSignalDBM: Int?

    /// Parses the `print` sub-object of one real MQTT report message.
    /// Returns `nil` only if the payload has no `print` key at all (e.g.
    /// a `system`-only message).
    init?(report: [String: Any]) {
        guard let print = report["print"] as? [String: Any] else { return nil }
        nozzleTemperature = Self.number(print["nozzle_temper"])
        nozzleTargetTemperature = Self.number(print["nozzle_target_temper"])
        bedTemperature = Self.number(print["bed_temper"])
        bedTargetTemperature = Self.number(print["bed_target_temper"])
        chamberTemperature = Self.number(print["chamber_temper"])
        let stateString = print["gcode_state"] as? String
        rawGCodeState = stateString
        gcodeState = stateString.flatMap(GCodeState.init(rawValue:))
        percentComplete = Self.integer(print["mc_percent"])
        remainingTimeMinutes = Self.integer(print["mc_remaining_time"])
        currentLayer = Self.integer(print["layer_num"])
        totalLayers = Self.integer(print["total_layer_num"])
        printError = Self.integer(print["print_error"])
        wifiSignalDBM = Self.integer(print["wifi_signal"])
    }

    /// The printer's firmware isn't consistent about numeric vs. string
    /// encoding across fields/firmware versions; accept either.
    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s) }
        return nil
    }
}

/// Real MQTT command payloads for `device/{serial}/request`
/// (RESEARCH-P0-007.md §"Command Request" + community-documented
/// pause/resume/stop command set — same reverse-engineered-protocol
/// basis already used by `SSDPNotifyParser`/`AMSMapping` in this repo).
extension PrinterConnection {
    private static var sequenceCounter = 0
    private func nextSequenceID() -> String {
        Self.sequenceCounter += 1
        return String(Self.sequenceCounter)
    }

    func pausePrint() throws {
        try send(["print": ["command": "pause", "sequence_id": nextSequenceID()]])
    }

    func resumePrint() throws {
        try send(["print": ["command": "resume", "sequence_id": nextSequenceID()]])
    }

    func stopPrint() throws {
        try send(["print": ["command": "stop", "sequence_id": nextSequenceID()]])
    }

    /// Starts a print of a `.3mf` already uploaded to
    /// `/sdcard/bbl_plater/` via `FTPSUploader` (only `.3mf` is
    /// startable this way per RESEARCH-P0-007.md's documented
    /// constraint — not `.gcode`).
    func startPrint(fileName: String, useAMS: Bool = false) throws {
        try send(["print": [
            "command": "project_file",
            "url": "file:///sdcard/bbl_plater/\(fileName)",
            "param": "Metadata/plate_1.gcode",
            "subtask_id": "0",
            "use_ams": useAMS,
            "timelapse": false,
            "flow_cali": false,
            "bed_leveling": true,
            "layer_inspect": true,
            "vibration_cali": false,
            "sequence_id": nextSequenceID(),
        ]])
    }
}
