import Foundation

/// A single Bambu config profile (machine/process/filament), as authored in
/// BambuStudio's `resources/profiles/BBL`. Values are loosely typed JSON
/// (mostly strings and string arrays) — no fixed schema upstream, so this
/// stays a raw dictionary rather than a fully-typed Codable model.
struct BambuProfile {
    let name: String
    let fields: [String: Any]

    var inherits: String? { fields["inherits"] as? String }
}

enum BambuProfileError: Error, Equatable {
    case profileNotFound(String)
    case missingAncestor(child: String, ancestor: String)
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

    /// Returns the fully-resolved field set for `name`: its own fields
    /// merged over every ancestor's fields, walking `inherits` to the root.
    func resolve(_ name: String) throws -> [String: Any] {
        guard let profile = profiles[name] else { throw BambuProfileError.profileNotFound(name) }
        var resolved: [String: Any] = [:]
        if let parentName = profile.inherits {
            guard profiles[parentName] != nil else {
                throw BambuProfileError.missingAncestor(child: name, ancestor: parentName)
            }
            resolved = try resolve(parentName)
        }
        for (key, value) in profile.fields {
            resolved[key] = value
        }
        return resolved
    }

    func profile(named name: String) -> BambuProfile? { profiles[name] }
    var allProfileNames: [String] { Array(profiles.keys) }
}
