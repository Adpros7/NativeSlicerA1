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
    struct ProfileSelection {
        var machine = "Bambu Lab A1 0.4 nozzle"
        var process = "0.20mm Standard @BBL A1"
        var filament = "Generic PLA @BBL A1"
    }

    /// Resolves `selection`'s three profiles (each already walks its own
    /// `inherits` chain via `BambuProfileLoader.resolve`) and merges them
    /// into one flat key/value list, serialized to libslic3r's own config
    /// string format (scalars as-is, arrays comma-joined — the same
    /// separator `ConfigBase::load_from_json` uses for everything except
    /// `coStrings`/`coPointsGroups`; comma-joining those too is a
    /// known simplification since none of the A1 single-material keys we
    /// set are string-list options that matter for slicing).
    static func resolvedConfigEntries(loader: BambuProfileLoader, selection: ProfileSelection = ProfileSelection()) throws -> [(key: String, value: String)] {
        var merged: [String: Any] = [:]
        for name in [selection.machine, selection.process, selection.filament] {
            let resolved = try loader.resolve(name)
            for (key, value) in resolved { merged[key] = value }
        }
        return merged.compactMap { key, value in
            serialize(value).map { (key, $0) }
        }
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

    /// Slices `objects` with the resolved A1 config and writes real G-code
    /// to `outputPath`.
    static func slice(
        objects: [(mesh: LoadedMesh, transform: simd_float4x4)],
        loader: BambuProfileLoader,
        selection: ProfileSelection = ProfileSelection(),
        outputPath: String
    ) throws {
        let entries = try resolvedConfigEntries(loader: loader, selection: selection)
        try SlicingEngine.sliceToGCode(objects: objects, configEntries: entries, outputPath: outputPath)
    }
}
