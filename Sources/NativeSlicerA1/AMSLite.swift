import Foundation

/// A single AMS Lite filament slot (RESEARCH-P0-008.md). AMS Lite has 4
/// slots (0–3), no humidity/temperature sensors, no drying — passive
/// spool holder with RFID/color/type reporting only.
struct AMSLiteSlot: Equatable {
    let id: Int
    let occupied: Bool
    let colorHex: String?   // RRGGBBAA
    let filamentType: String?
    let remainPercent: Int?
}

/// Parsed state of a single AMS Lite unit from an MQTT `print.ams` report.
struct AMSLiteState: Equatable {
    let unitID: Int
    let slots: [AMSLiteSlot] // always 4, ordered by slot id
    let activeTray: Int?     // tray_now; nil if unset/255 (external spool)

    /// Parses one entry of the `print.ams.ams` array (a single AMS/AMS-Lite
    /// unit), e.g.:
    /// `{"id": 0, "tray": [{"id":0,"tray_color":"FF0000FF","tray_type":"PLA","remain":80}, ...]}`
    /// combined with the report-level `tray_exist_bits` hex bitmask and
    /// `tray_now`.
    init?(unit: [String: Any], trayExistBitsHex: String?, trayNow: String?) {
        guard let id = unit["id"] as? Int else { return nil }
        unitID = id

        let occupancy = Self.decodeOccupancy(trayExistBitsHex)
        let trayArray = (unit["tray"] as? [[String: Any]]) ?? []
        var bySlot: [Int: [String: Any]] = [:]
        for tray in trayArray {
            if let tid = tray["id"] as? Int { bySlot[tid] = tray }
            else if let tidStr = tray["id"] as? String, let tid = Int(tidStr) { bySlot[tid] = tray }
        }

        slots = (0..<4).map { slotID in
            let tray = bySlot[slotID]
            return AMSLiteSlot(
                id: slotID,
                occupied: occupancy[slotID] ?? (tray != nil),
                colorHex: tray?["tray_color"] as? String,
                filamentType: tray?["tray_type"] as? String,
                remainPercent: tray?["remain"] as? Int
            )
        }

        if let trayNow, let value = Int(trayNow), value != 255, value != 254 {
            activeTray = value
        } else {
            activeTray = nil
        }
    }

    /// Decodes `tray_exist_bits` (a hex string bitmask, e.g. "e" = 0b1110 =
    /// slots 1,2,3 occupied) into a slot-id -> occupied map.
    private static func decodeOccupancy(_ hex: String?) -> [Int: Bool] {
        guard let hex, let bits = Int(hex, radix: 16) else { return [:] }
        var result: [Int: Bool] = [:]
        for slot in 0..<4 {
            result[slot] = (bits & (1 << slot)) != 0
        }
        return result
    }
}

/// Builds the `ams_mapping` array for an MQTT print command
/// (RESEARCH-P0-008.md §5): fixed 5 elements, right-to-left assignment,
/// `-1` padding on unused leading positions.
enum AMSMapping {
    /// - Parameter slotsByColorIndex: slot id for each project color index,
    ///   in color order (index 0 = first color). Must have 1–4 entries.
    static func build(slotsByColorIndex: [Int]) -> [Int] {
        precondition((1...4).contains(slotsByColorIndex.count), "AMS mapping supports 1-4 colors")
        let padding = Array(repeating: -1, count: 5 - slotsByColorIndex.count)
        return padding + slotsByColorIndex
    }
}
