import Foundation

/// A single Bambu config profile (machine/process/filament), as authored in
/// BambuStudio's `resources/profiles/BBL`. Values are loosely typed JSON
/// (mostly strings and string arrays) — no fixed schema upstream, so this
/// stays a raw dictionary rather than a fully-typed Codable model.
struct BambuProfile {
    let name: String
    let fields: [String: Any]

    var inherits: String? { fields["inherits"] as? String }
    /// Sibling fragment profiles merged in after the `inherits` chain but
    /// before this profile's own fields (see `resolve` below) — e.g. the
    /// A1 0.4 nozzle machine profile's per-nozzle custom G-code templates
    /// (`machine_start_gcode`/`machine_end_gcode`/etc., each its own
    /// `"instantiation": "false"` template file, not independently
    /// selectable). Upstream key: `BBL_JSON_KEY_INCLUDES` ("include"),
    /// `PresetBundle.cpp`.
    var includes: [String] { fields["include"] as? [String] ?? [] }
    /// `"machine"`/`"process"`/`"filament"`.
    var type: String? { fields["type"] as? String }
    /// Whether this profile is directly user-selectable, vs. an abstract
    /// ancestor (`fdm_machine_common`) or `include` template fragment
    /// (`instantiation == "false"`) — the same filter BambuStudio's own
    /// preset picker uses (P3-003).
    var isInstantiable: Bool { (fields["instantiation"] as? String) == "true" }
    /// Machine profile names this process/filament profile is declared
    /// compatible with; `nil` means no declared restriction (every
    /// vendored A1 process/filament profile declares this).
    var compatiblePrinters: [String]? { fields["compatible_printers"] as? [String] }
}

enum BambuProfileError: Error, Equatable {
    case profileNotFound(String)
    case missingAncestor(child: String, ancestor: String)
    /// `profile` isn't declared compatible with `machine` (P3-003
    /// validation — `compatible_printers` doesn't list `machine`).
    case incompatibleProfile(profile: String, machine: String)
}

/// Loads vendored Bambu A1 printer/process/filament profiles and resolves
/// their `inherits` chains the same way BambuStudio's config system does:
/// child fields override parent fields, recursively up to the root.
///
/// Scope: only the Bambu Lab A1 profile closure is vendored (see
/// `Resources/Profiles/BBL`) — not the full multi-printer fleet, per
/// SPEC.md's A1-only scope.
struct BambuProfileLoader {
    private var profiles: [String: BambuProfile] = [:]

    init(bundle: Bundle = .module) throws {
        guard let root = bundle.url(forResource: "BBL", withExtension: nil, subdirectory: "Profiles") else {
            throw BambuProfileError.profileNotFound("Profiles/BBL resource root")
        }
        let subdirs = ["machine", "process", "filament"]
        let fm = FileManager.default
        for sub in subdirs {
            let dir = root.appendingPathComponent(sub)
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "json" {
                let data = try Data(contentsOf: file)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let name = file.deletingPathExtension().lastPathComponent
                profiles[name] = BambuProfile(name: name, fields: json)
            }
        }
    }

    /// Returns the fully-resolved field set for `name`: its ancestor
    /// chain's fields (via `inherits`, recursively to the root), then each
    /// `include` fragment's own fields merged on top in list order, then
    /// `name`'s own fields winning last — the same three-tier precedence
    /// `PresetBundle.cpp`'s `load_system_models`/`load_system_filaments`
    /// use (`config = *default_config` → `config.apply_only(include_config,
    /// include_config.diff(include_default_config))` per include → `config
    /// .apply(config_src)`). Each `include` profile is a flat template with
    /// no `inherits` of its own (verified: every vendored `*template*gcode*
    /// .json` has exactly one real field besides `name`/`instantiation`),
    /// so using its fields directly is equivalent to upstream's
    /// diff-against-default restriction without needing the full default
    /// closure here — downstream (`nsa1_slice_to_gcode`) already drops any
    /// resolved key that isn't a real engine config option, so template
    /// metadata (`name`/`instantiation`) merged in along the way is inert.
    func resolve(_ name: String) throws -> [String: Any] {
        guard let profile = profiles[name] else { throw BambuProfileError.profileNotFound(name) }
        var resolved: [String: Any] = [:]
        if let parentName = profile.inherits {
            guard profiles[parentName] != nil else {
                throw BambuProfileError.missingAncestor(child: name, ancestor: parentName)
            }
            resolved = try resolve(parentName)
        }
        for includeName in profile.includes {
            guard let includeProfile = profiles[includeName] else {
                throw BambuProfileError.missingAncestor(child: name, ancestor: includeName)
            }
            for (key, value) in includeProfile.fields { resolved[key] = value }
        }
        for (key, value) in profile.fields {
            resolved[key] = value
        }
        return resolved
    }

    func profile(named name: String) -> BambuProfile? { profiles[name] }
    var allProfileNames: [String] { Array(profiles.keys) }

    /// Vendored A1 profile names of `type` ("machine"/"process"/
    /// "filament") that are directly user-selectable, sorted for stable
    /// UI ordering (P3-003 printer/process/filament pickers).
    func instantiableProfileNames(type: String) -> [String] {
        profiles.values.filter { $0.type == type && $0.isInstantiable }.map(\.name).sorted()
    }

    /// Whether `name` (a process or filament profile) is declared
    /// compatible with `machineName` — the same `compatible_printers`
    /// check BambuStudio's own preset picker uses to grey out invalid
    /// combinations (P3-003 "invalid combinations rejected safely").
    /// Unknown `name` is treated as incompatible.
    func isCompatible(_ name: String, withMachine machineName: String) -> Bool {
        guard let profile = profiles[name] else { return false }
        guard let list = profile.compatiblePrinters else { return true }
        return list.contains(machineName)
    }
}
