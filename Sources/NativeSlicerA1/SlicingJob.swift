import Foundation
import simd

/// Drives P1-008: resolves the vendored Bambu A1 machine/process/filament
/// profile closure (`BambuProfileLoader`) into a flat config entry list and
/// slices placed scene objects into real G-code via the engine bridge
/// (`SlicingEngine.sliceToGCode`, which runs libslic3r's own
/// `Print::apply`/`validate`/`process`/`export_gcode` pipeline).
enum SlicingJob {
    /// A single-nozzle/single-material A1 profile selection — the same
    /// presets BambuStudio ships as its own A1 defaults (SPEC.md A1-only
    /// scope: no AMS/multi-material here, see P2-006 for AMS mapping).
    /// AMS Lite compatibility note: every vendored A1 filament profile is
    /// one AMS Lite already validates against (RESEARCH-P0-008.md) — no
    /// separate "AMS Lite" filter is needed here, picking from this list
    /// is already AMS-Lite-safe.
    struct ProfileSelection: Equatable {
        var machine = "Bambu Lab A1 0.4 nozzle"
        var process = "0.20mm Standard @BBL A1"
        var filament = "Generic PLA @BBL A1"
        /// User-adjustable overrides on top of the resolved profile
        /// (P3-003), keyed by real libslic3r config option name (e.g.
        /// `"layer_height"`) — see `overridableKeys`. Applied last, so
        /// they win over whatever the selected process/filament profile
        /// sets for the same key.
        var overrides: [String: String] = [:]
    }

    /// The handful of common settings P3-003's UI exposes directly,
    /// mapped to their real libslic3r `PrintConfig.cpp` option names —
    /// `layer_height` (coFloat), `wall_loops` (coInt),
    /// `sparse_infill_density` (coPercent), `enable_support` (coBool),
    /// `nozzle_temperature` (coInts, per-extruder), `hot_plate_temp`
    /// (coInts, per-extruder bed temperature). Single source of truth for
    /// both the settings UI and project persistence's override restore.
    static let overridableKeys = [
        "layer_height", "wall_loops", "sparse_infill_density",
        "enable_support", "nozzle_temperature", "hot_plate_temp",
    ]

    /// Validates `selection`'s process/filament profiles are declared
    /// compatible with its machine profile (same `compatible_printers`
    /// check BambuStudio's own preset picker uses) — P3-003's "invalid
    /// combinations are rejected safely" requirement. Called automatically
    /// by `resolvedConfigEntries`/`slice`, so every slice and every
    /// project save is validated, not just UI-level picker filtering.
    static func validate(_ selection: ProfileSelection, loader: BambuProfileLoader) throws {
        guard loader.isCompatible(selection.process, withMachine: selection.machine) else {
            throw BambuProfileError.incompatibleProfile(profile: selection.process, machine: selection.machine)
        }
        guard loader.isCompatible(selection.filament, withMachine: selection.machine) else {
            throw BambuProfileError.incompatibleProfile(profile: selection.filament, machine: selection.machine)
        }
    }

    /// Resolves `selection`'s three profiles (each already walks its own
    /// `inherits`/`include` chain via `BambuProfileLoader.resolve`) and
    /// merges them into one flat key/value list, serialized to
    /// libslic3r's own config string format (scalars as-is, arrays
    /// comma-joined — the same separator `ConfigBase::load_from_json`
    /// uses for everything except `coStrings`/`coPointsGroups`;
    /// comma-joining those too is a known simplification since none of
    /// the A1 single-material keys we set are string-list options that
    /// matter for slicing). Also records which profiles were selected
    /// (`printer_settings_id`/`print_settings_id`/`filament_settings_id`
    /// — the same real engine keys BambuStudio itself uses to remember a
    /// project's profile choice) so `restoreSelection` can read them back
    /// after a save/reload (P3-003 persistence), and applies
    /// `selection.overrides` last so they win over the profile defaults.
    static func resolvedConfigEntries(loader: BambuProfileLoader, selection: ProfileSelection = ProfileSelection()) throws -> [(key: String, value: String)] {
        try validate(selection, loader: loader)
        var merged: [String: Any] = [:]
        for name in [selection.machine, selection.process, selection.filament] {
            let resolved = try loader.resolve(name)
            for (key, value) in resolved { merged[key] = value }
        }
        merged["printer_settings_id"] = selection.machine
        merged["print_settings_id"] = selection.process
        merged["filament_settings_id"] = [selection.filament]
        for (key, value) in selection.overrides { merged[key] = value }
        return merged.compactMap { key, value in
            serialize(value).map { (key, $0) }
        }
    }

    /// Reconstructs a `ProfileSelection` from config entries previously
    /// read back via `SlicingEngine.loadThreeMFConfig` (P3-003
    /// persistence) — the inverse of `resolvedConfigEntries`'s
    /// `*_settings_id`/override bookkeeping. Falls back to
    /// `ProfileSelection()`'s defaults for any key a pre-P3-003 project
    /// (or one with no embedded config at all) doesn't have.
    static func restoreSelection(from configEntries: [(key: String, value: String)]) -> ProfileSelection {
        var byKey: [String: String] = [:]
        for (key, value) in configEntries { byKey[key] = value }
        var selection = ProfileSelection()
        if let machine = byKey["printer_settings_id"] { selection.machine = machine }
        if let process = byKey["print_settings_id"] { selection.process = process }
        // `filament_settings_id` is libslic3r's `coStrings` (array) type:
        // reading it back serializes through `ConfigOptionStrings::
        // serialize()`'s real C-style escaping (`escape_strings_cstyle`,
        // `Config.cpp`), which quotes any element containing a space —
        // every vendored A1 filament profile name does. Strip that one
        // surrounding quote pair back off; our naive write-side
        // comma-join (`serialize(_:)` below) never added it, so
        // `set_deserialize` happily accepted the unquoted form going in
        // (its own parser only quote-wraps when deserializing an
        // already-quoted string), but the engine's own `serialize()`
        // always re-applies real quoting coming back out.
        if var filament = byKey["filament_settings_id"] {
            if filament.hasPrefix("\""), filament.hasSuffix("\""), filament.count >= 2 {
                filament.removeFirst()
                filament.removeLast()
            }
            selection.filament = filament
        }
        for key in overridableKeys {
            if let value = byKey[key] { selection.overrides[key] = value }
        }
        return selection
    }

    private static func serialize(_ value: Any) -> String? {
        if let s = value as? String { return s }
        if let arr = value as? [Any] {
            guard !arr.isEmpty else { return nil } // nothing to override; keep engine default
            let parts = arr.compactMap { serialize($0) }
            return parts.joined(separator: ",")
        }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    /// Slices `objects` with the resolved A1 config, writes real G-code to
    /// `outputPath`, and returns the real per-move toolpath (P1-009) for
    /// viewport preview.
    @discardableResult
    static func slice(
        objects: [(mesh: LoadedMesh, transform: simd_float4x4)],
        loader: BambuProfileLoader,
        selection: ProfileSelection = ProfileSelection(),
        outputPath: String,
        paintData: [[UInt8]] = []
    ) throws -> [ToolpathSegment] {
        let entries = try resolvedConfigEntries(loader: loader, selection: selection)
        return try SlicingEngine.sliceToGCode(objects: objects, configEntries: entries, outputPath: outputPath, paintData: paintData)
    }
}
