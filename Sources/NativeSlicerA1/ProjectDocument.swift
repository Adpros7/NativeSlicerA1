import Foundation
import simd

/// Owns the in-memory scene: loaded meshes (by id) and the placed objects
/// that reference them. The only mutation paths are `importModel`,
/// `apply(_:to:)`, and `removeObject` — geometry itself is never edited,
/// only referenced, per SPEC.md §9's non-destructive requirement.
@MainActor
final class ProjectDocument: ObservableObject {
    @Published private(set) var meshes: [UUID: LoadedMesh] = [:]
    @Published private(set) var objects: [SceneObject] = []
    @Published var selection: UUID?
    @Published var lastError: String?

    func mesh(for object: SceneObject) -> LoadedMesh? { meshes[object.sourceMeshID] }

    /// Imports an STL or 3MF file, adding one scene object per mesh found
    /// (a 3MF can contain multiple model objects; `.3mf` imports also
    /// restore each object's saved placement).
    func importModel(at url: URL) {
        do {
            let imported = try loadScene(at: url)
            meshes.merge(imported.meshes) { _, new in new }
            objects.append(contentsOf: imported.objects)
            selection = imported.objects.last?.id ?? selection
            lastError = nil
        } catch {
            lastError = "Import failed: \(error)"
        }
    }

    /// Loads all file data into temporary value collections before exposing
    /// it to the scene, so an unreadable/partly-invalid project cannot
    /// leave the user with a partially mutated document.
    private func loadScene(at url: URL) throws -> (meshes: [UUID: LoadedMesh], objects: [SceneObject]) {
        let loaded: [(mesh: LoadedMesh, transform: Transform)]
        switch url.pathExtension.lowercased() {
        case "stl":
            loaded = [(try SlicingEngine.loadSTLMesh(atPath: url.path), .identity)]
        case "3mf":
            let count = try SlicingEngine.threeMFObjectCount(atPath: url.path)
            loaded = try (0..<count).map { index in
                (
                    try SlicingEngine.loadThreeMFMesh(atPath: url.path, objectIndex: index),
                    Transform(matrix: try SlicingEngine.threeMFObjectTransform(atPath: url.path, objectIndex: index))
                )
            }
        default:
            throw SlicingEngineError.unsupportedFileType(url.pathExtension)
        }

        var meshes: [UUID: LoadedMesh] = [:]
        let objects = loaded.map { item in
            let meshID = UUID()
            meshes[meshID] = item.mesh
            return SceneObject(sourceMeshID: meshID, transform: item.transform)
        }
        return (meshes, objects)
    }

    func apply(_ transform: Transform, to objectID: UUID) {
        guard let i = objects.firstIndex(where: { $0.id == objectID }) else { return }
        objects[i].apply(transform)
    }

    func undo(_ objectID: UUID) {
        guard let i = objects.firstIndex(where: { $0.id == objectID }) else { return }
        objects[i].undo()
    }

    func redo(_ objectID: UUID) {
        guard let i = objects.firstIndex(where: { $0.id == objectID }) else { return }
        objects[i].redo()
    }

    func removeObject(_ objectID: UUID) {
        guard let object = objects.first(where: { $0.id == objectID }) else { return }
        objects.removeAll { $0.id == objectID }
        meshes.removeValue(forKey: object.sourceMeshID)
        if selection == objectID { selection = nil }
    }

    /// Saves the scene as a 3MF project file via the real engine's
    /// `store_3mf` (P1-007) — the same format/writer BambuStudio and
    /// OrcaSlicer use for their own project files.
    func save(to url: URL) {
        let payload = objects.compactMap { object -> (mesh: LoadedMesh, transform: simd_float4x4)? in
            guard let mesh = meshes[object.sourceMeshID] else { return nil }
            return (mesh, object.transform.matrix)
        }
        do {
            try SlicingEngine.storeThreeMF(atPath: url.path, objects: payload)
        } catch {
            lastError = "Save failed: \(error)"
        }
    }

    /// Loads a previously saved 3MF project. The current scene is replaced
    /// only after the complete new scene has been parsed successfully.
    func load(from url: URL) {
        do {
            let loaded = try loadScene(at: url)
            meshes = loaded.meshes
            objects = loaded.objects
            selection = loaded.objects.last?.id
            lastError = nil
        } catch {
            lastError = "Load failed: \(error)"
        }
    }
}
