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
    @Published private(set) var toolpath: [ToolpathSegment] = []
    @Published private(set) var isSlicing = false
    /// G-code toolpath view mode (P1-012): controls how segments are colored.
    /// G-code toolpath view mode (P1-012): controls how segments are colored.
    @Published var toolpathViewMode: ToolpathViewMode = .featureType
    @Published private(set) var lastCalibration: CalibrationGeneration?
    /// (P3-003) — applied by `slice()` and persisted by `save(to:)`/
    /// `load(from:)` via the 3MF project's embedded config.
    @Published var profileSelection = SlicingJob.ProfileSelection()
    /// P4-008 batch-job plate grouping — always at least one plate.
    @Published private(set) var plates: [Plate]
    @Published var activePlateID: UInt64

    init() {
        let plate = Plate(name: "Plate 1")
        plates = [plate]
        activePlateID = plate.id
    }


    /// P3-005 support-paint UI state: whether the viewport is in paint
    /// mode (click-drag paints instead of orbiting the camera), the
    /// active brush radius (mm), and brush type.
    @Published var paintMode = false
    @Published var paintBrushRadius: Float = 5
    @Published var paintType: SupportPaintType = .enforcer
    /// Real `TriangleSelector`-backed paint session per object, created
    /// lazily on first paint stroke. Absent entries mean "unpainted".
    private var paintStates: [UUID: SupportPaintState] = [:]

    /// Paints a spherical brush stroke at `localPoint` (the target
    /// object's own local mesh coordinates, e.g. from
    /// `rayMeshIntersection`) onto `objectID`'s real paint session,
    /// creating one via `nsa1_paint_create` if this is its first stroke.
    func paintAt(objectID: UUID, localPoint: SIMD3<Float>) {
        guard let object = objects.first(where: { $0.id == objectID }), let mesh = meshes[object.sourceMeshID] else { return }
        let state = paintStates[objectID] ?? SupportPaintState(mesh: mesh)
        guard let state else { return }
        paintStates[objectID] = state
        state.paintSphere(center: localPoint, radius: paintBrushRadius, type: paintType)
        objectWillChange.send()
    }

    /// Whether `objectID` has any painted support data.
    func hasPaintData(for objectID: UUID) -> Bool { paintStates[objectID] != nil }

    func canUndoPaint(for objectID: UUID) -> Bool { paintStates[objectID]?.canUndo == true }
    func canRedoPaint(for objectID: UUID) -> Bool { paintStates[objectID]?.canRedo == true }

    func undoPaint(for objectID: UUID) {
        guard paintStates[objectID]?.undo() == true else { return }
        objectWillChange.send()
    }

    func redoPaint(for objectID: UUID) {
        guard paintStates[objectID]?.redo() == true else { return }
        objectWillChange.send()
    }

    func mesh(for object: SceneObject) -> LoadedMesh? { meshes[object.sourceMeshID] }
    /// World-space axis-aligned bounding box of `object`'s mesh after
    /// applying its placement transform — used to size/center the
    /// interactive cut plane (P4-006 prerequisite) sensibly for whatever
    /// object is selected.
    func worldBoundingBox(for object: SceneObject) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard let mesh = meshes[object.sourceMeshID], !mesh.vertices.isEmpty else { return nil }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        let m = object.transform.matrix
        var i = 0
        while i < mesh.vertices.count {
            let local = SIMD4<Float>(mesh.vertices[i], mesh.vertices[i + 1], mesh.vertices[i + 2], 1)
            let world4 = m * local
            let world = SIMD3(world4.x, world4.y, world4.z) / world4.w
            lo = SIMD3(x: Swift.min(lo.x, world.x), y: Swift.min(lo.y, world.y), z: Swift.min(lo.z, world.z))
            hi = SIMD3(x: Swift.max(hi.x, world.x), y: Swift.max(hi.y, world.y), z: Swift.max(hi.z, world.z))
            i += 3
        }
        return (lo, hi)
    }

    /// P4-006 interactive cut-plane state: whether the viewport is in
    /// cut-plane mode, the plane itself (nil until a selected object
    /// initializes one), and which parts to keep on `performCut()`.
    @Published var cutPlaneMode = false {
        didSet {
            if cutPlaneMode {
                beginCutPlane()
            } else {
                cutPlane = nil
                cutConnectors = []
                selectedCutConnectorID = nil
                connectorPlacementMode = false
            }
        }
    }
    @Published var cutPlane: CutPlane?
    @Published var cutKeepMode: CutMode = .both
    /// P4-006 pending connector inputs for the active cut only. These
    /// become real upstream cut-connector volumes at cut time; source
    /// mesh data remains untouched while editing them.
    @Published private(set) var cutConnectors: [CutConnectorPlacement] = []
    @Published var selectedCutConnectorID: UUID?
    /// Routes the next viewport click to the active plane instead of
    /// moving the plane itself: each click adds one connector placement.
    @Published var connectorPlacementMode = false

    /// P4-007: scene-composition undo for the cut operation itself,
    /// reusing the existing generic `UndoStack` (not a parallel history
    /// mechanism) — separate from each `SceneObject`'s own per-object
    /// `transformHistory`, since a cut replaces objects wholesale rather
    /// than adjusting one object's transform.
    private var cutHistory: UndoStack<[SceneObject]>?
    var canUndoCut: Bool { cutHistory?.canUndo ?? false }
    var canRedoCut: Bool { cutHistory?.canRedo ?? false }

    func undoCut() {
        guard var history = cutHistory, history.canUndo else { return }
        objects = history.undo()
        cutHistory = history
    }

    func redoCut() {
        guard var history = cutHistory, history.canRedo else { return }
        objects = history.redo()
        cutHistory = history
    }

    /// Initializes `cutPlane` centered on the selected object's own
    /// world-space bounding box center, flat (no tilt), sized to
    /// comfortably exceed the object's own footprint.
    func beginCutPlane() {
        guard let selection, let object = objects.first(where: { $0.id == selection }),
              let box = worldBoundingBox(for: object) else {
            cutPlane = nil
            return
        }
        let center = (box.min + box.max) * 0.5
        let size = box.max - box.min
        let extent = Swift.max(size.x, size.y, size.z, 10) * 1.5
        cutPlane = CutPlane(center: center, halfExtent: extent)
    }

    func setCutPlaneCenter(_ center: SIMD3<Float>) {
        cutPlane?.center = center
    }

    func setCutPlaneTilt(x: Float? = nil, y: Float? = nil) {
        if let x { cutPlane?.tiltX = x }
        if let y { cutPlane?.tiltY = y }
    }

    /// Adds a default real-engine connector preset at a world-space point
    /// on the active cut plane, selects it for property editing, and
    /// leaves the source object/mesh non-destructively unchanged.
    func addConnector(at position: SIMD3<Float>) {
        guard cutPlane != nil else { return }
        let connector = CutConnectorPlacement(position: position)
        cutConnectors.append(connector)
        selectedCutConnectorID = connector.id
    }

    func removeSelectedConnector() {
        guard let selectedCutConnectorID else { return }
        cutConnectors.removeAll { $0.id == selectedCutConnectorID }
        self.selectedCutConnectorID = nil
    }

    func updateSelectedConnector(_ update: (inout CutConnectorPlacement) -> Void) {
        guard let id = selectedCutConnectorID,
              let index = cutConnectors.firstIndex(where: { $0.id == id })
        else { return }
        update(&cutConnectors[index])
    }

    /// Performs the real cut (P4-006) via `SlicingEngine.cutModel` using
    /// the current `cutPlane`/`cutKeepMode`, replacing the selected
    /// object with the real resulting part(s) — matching the real
    /// engine's own Cut tool behavior (the source object is consumed by
    /// the cut, not kept alongside its own pieces). Mesh data for the
    /// results comes directly from the real engine, never recomputed in
    /// Swift. Paint/layer-height overrides on the original do not carry
    /// over (matches upstream: `ModelObject::cut` resets
    /// `supported_facets` on cut volumes, and layer-height ranges are a
    /// Z-range property of the pre-cut object's own geometry).
    func performCut() {
        guard let plane = cutPlane,
              let selectedID = selection,
              let index = objects.firstIndex(where: { $0.id == selectedID }),
              let mesh = meshes[objects[index].sourceMeshID]
        else { return }
        let transform = objects[index].transform.matrix
        let connectorInputs: [(position: SIMD3<Float>, normal: SIMD3<Float>, preset: ConnectorPreset)] =
            cutConnectors.map { (position: $0.position, normal: plane.normal, preset: $0.preset) }
        do {
            let results = try SlicingEngine.cutModel(
                objects: [(mesh: mesh, transform: transform)],
                planePoints: plane.planePoints,
                cutMode: cutKeepMode,
                connectors: connectorInputs
            )
            guard !results.isEmpty else {
                lastError = "Cut produced no geometry — check the plane actually intersects the object."
                return
            }
            // P4-007: snapshot scene composition before mutating, so
            // undoCut()/redoCut() can restore it exactly. The removed
            // object's mesh is deliberately NOT deleted from `meshes`
            // even if briefly unreferenced — undo needs it back, and an
            // orphaned LoadedMesh is a bounded, acceptable cost for
            // correct reversibility (no parallel storage mechanism).
            if cutHistory == nil {
                cutHistory = UndoStack(initial: objects)
            }
            let originalPlateID = objects[index].plateID
            objects.remove(at: index)
            let cutGroupID = UInt64.random(in: 1...UInt64.max) // 0 means "not cut"
            var newIDs: [UUID] = []
            for result in results {
                let meshID = UUID()
                meshes[meshID] = result.mesh
                let newObject = SceneObject(sourceMeshID: meshID, transform: Transform(matrix: result.transform), cutGroupID: cutGroupID, plateID: originalPlateID)
                objects.append(newObject)
                newIDs.append(newObject.id)
            }
            cutHistory?.push(objects)
            selection = newIDs.first
            cutPlaneMode = false
            lastError = nil
        } catch {
            lastError = "Cut failed: \(error)"
        }
    }

    /// Imports an STL or 3MF file, adding one scene object per mesh found
    /// (a 3MF can contain multiple model objects; `.3mf` imports also
    /// restore each object's saved placement).
    func importModel(at url: URL) {
        do {
            let imported = try loadScene(at: url, defaultPlateID: activePlateID)
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
    private func loadScene(at url: URL, defaultPlateID: UInt64) throws -> (meshes: [UUID: LoadedMesh], objects: [SceneObject]) {
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
            return SceneObject(sourceMeshID: meshID, transform: item.transform, plateID: defaultPlateID)
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

    /// Replaces object `objectID`'s P4-014 variable layer height
    /// overrides wholesale (simple value replacement, no undo stack —
    /// matches the minimal-state approach of other non-geometric scene
    /// properties; re-slicing picks up the new ranges automatically).
    func setLayerHeightRanges(_ ranges: [LayerHeightRange], for objectID: UUID) {
        guard let i = objects.firstIndex(where: { $0.id == objectID }) else { return }
        objects[i].layerHeightRanges = ranges
    }

    func removeObject(_ objectID: UUID) {
        guard let object = objects.first(where: { $0.id == objectID }) else { return }
        objects.removeAll { $0.id == objectID }
        paintStates.removeValue(forKey: objectID)
        meshes.removeValue(forKey: object.sourceMeshID)
        if selection == objectID { selection = nil }
    }

    /// All objects currently placed on `activePlateID` — the subset the
    /// viewport, slicer, and auto-arrange operate on for batch workflows.
    var objectsOnActivePlate: [SceneObject] {
        objects.filter { $0.plateID == activePlateID }
    }

    /// P4-009: real per-object world-space XY footprint on the active
    /// plate, projected into bed-relative coordinates (bed origin at
    /// its own corner, matching the A1's real coordinate convention) —
    /// what a 2D plate preview/thumbnail needs, and a real "does this
    /// fit on the bed" check, not placeholder rendering. Reuses the
    /// same real `worldBoundingBox` the P4-006 cut plane already uses.
    struct PlatePreviewEntry {
        let objectID: UUID
        let minX: Float
        let minY: Float
        let maxX: Float
        let maxY: Float
        let withinBed: Bool
    }

    func platePreview(bedWidth: Float, bedHeight: Float) -> [PlatePreviewEntry] {
        objectsOnActivePlate.compactMap { object in
            guard let box = worldBoundingBox(for: object) else { return nil }
            let withinBed = box.min.x >= 0 && box.min.y >= 0 && box.max.x <= bedWidth && box.max.y <= bedHeight
            return PlatePreviewEntry(
                objectID: object.id,
                minX: box.min.x, minY: box.min.y, maxX: box.max.x, maxY: box.max.y,
                withinBed: withinBed
            )
        }
    }

    /// Creates a new empty plate and returns its id; does not switch
    /// `activePlateID` (callers choose when to switch, matching
    /// `addConnector`/other explicit-mutation methods in this file).
    @discardableResult
    func addPlate(name: String? = nil) -> UInt64 {
        let plate = Plate(name: name ?? "Plate \(plates.count + 1)")
        plates.append(plate)
        return plate.id
    }

    /// Removes `plateID`, reassigning its objects to the first remaining
    /// plate rather than deleting them — a batch-job queue must never
    /// silently discard placed geometry. No-op if `plateID` is the only
    /// plate (a project always has at least one).
    func removePlate(_ plateID: UInt64) {
        guard plates.count > 1, let index = plates.firstIndex(where: { $0.id == plateID }) else { return }
        plates.remove(at: index)
        let fallback = plates[0].id
        for i in objects.indices where objects[i].plateID == plateID {
            objects[i].plateID = fallback
        }
        if activePlateID == plateID { activePlateID = fallback }
    }

    /// Auto-arranges only `objectsOnActivePlate` via the real engine's
    /// libnest2d-backed `SlicingEngine.autoArrange` (P4-011) — other
    /// plates' objects are excluded entirely, never used as packing
    /// obstacles for this plate's real convex-hull-based arrangement.
    func autoArrangeActivePlate(bedWidth: Double, bedHeight: Double, clearance: Double) async throws {
        let plateObjects = objectsOnActivePlate
        guard !plateObjects.isEmpty else { return }
        let meshInputs: [(vertices: [Float], indices: [UInt32], matrix: simd_float4x4)] = plateObjects.compactMap { object in
            guard let mesh = meshes[object.sourceMeshID] else { return nil }
            return (mesh.vertices, mesh.indices, object.transform.matrix)
        }
        let results = try SlicingEngine.autoArrange(
            meshes: meshInputs, bedWidth: bedWidth, bedHeight: bedHeight, clearance: clearance)
        for (object, result) in zip(plateObjects, results) {
            guard let i = objects.firstIndex(where: { $0.id == object.id }) else { continue }
            var transform = objects[i].transform
            transform.translation += SIMD3(Float(result.x), Float(result.y), 0)
            transform.rotation = simd_quatf(angle: Float(result.rotation), axis: SIMD3(0, 0, 1)) * transform.rotation
            objects[i].apply(transform)
        }
    }

    /// Saves the scene as a 3MF project file via the real engine's
    /// `store_3mf`, including resolved profile config (P3-003) and
    /// TriangleSelector-backed support paint (P3-005), so both profile
    /// selection and painted facets survive a save/reload round trip.
    func save(to url: URL) {
        var payload: [(mesh: LoadedMesh, transform: simd_float4x4)] = []
        var paintData: [[UInt8]] = []
        var cutGroupIDs: [UInt64?] = []
        var plateIDs: [UInt64] = []
        for object in objects {
            guard let mesh = meshes[object.sourceMeshID] else { continue }
            payload.append((mesh, object.transform.matrix))
            paintData.append(paintStates[object.id]?.serialize() ?? [])
            cutGroupIDs.append(object.cutGroupID)
            plateIDs.append(object.plateID)
        }
        do {
            let loader = try BambuProfileLoader()
            let configEntries = try SlicingJob.resolvedConfigEntries(loader: loader, selection: profileSelection)
            try SlicingEngine.storeThreeMF(
                atPath: url.path, objects: payload, configEntries: configEntries,
                paintData: paintData, cutGroupIDs: cutGroupIDs)
            try SlicingEngine.storeThreeMFPlateIDs(atPath: url.path, objectCount: payload.count, plateIDs: plateIDs)
            lastError = nil
        } catch {
            lastError = "Save failed: \(error)"
        }
    }

    /// Loads a previously saved 3MF project, including its embedded
    /// profile selection/overrides (P3-003) if present. The current scene
    /// is replaced only after the complete new scene has been parsed
    /// successfully.
    func load(from url: URL) {
        do {
            let loaded = try loadScene(at: url, defaultPlateID: activePlateID)
            let configEntries = SlicingEngine.loadThreeMFConfig(atPath: url.path)
            var restoredPaintStates: [UUID: SupportPaintState] = [:]
            var restoredObjects = loaded.objects
            if url.pathExtension.lowercased() == "3mf" {
                for (index, object) in loaded.objects.enumerated() {
                    let data = SlicingEngine.loadThreeMFPaint(atPath: url.path, objectIndex: index)
                    if !data.isEmpty,
                       let mesh = loaded.meshes[object.sourceMeshID],
                       let state = SupportPaintState(mesh: mesh),
                       state.deserialize(data) {
                        restoredPaintStates[object.id] = state
                    }
                    restoredObjects[index].cutGroupID = SlicingEngine.loadThreeMFCutGroupID(atPath: url.path, objectIndex: index)
                    if let plateID = SlicingEngine.loadThreeMFPlateID(atPath: url.path, objectIndex: index) {
                        restoredObjects[index].plateID = plateID
                    }
                }
            }
            // Reconstruct the plates list from the distinct plate ids
            // actually referenced by the loaded objects (first-seen
            // order) — the plate LIST itself isn't separately persisted,
            // only each object's assignment, which is sufficient to
            // fully reconstruct it.
            var seenPlateIDs: [UInt64] = []
            for object in restoredObjects where !seenPlateIDs.contains(object.plateID) {
                seenPlateIDs.append(object.plateID)
            }
            let restoredPlates = seenPlateIDs.isEmpty
                ? [Plate(name: "Plate 1")]
                : seenPlateIDs.enumerated().map { index, id in Plate(id: id, name: "Plate \(index + 1)") }
            meshes = loaded.meshes
            objects = restoredObjects
            paintStates = restoredPaintStates
            plates = restoredPlates
            activePlateID = restoredPlates[0].id
            selection = restoredObjects.last?.id
            profileSelection = SlicingJob.restoreSelection(from: configEntries)
            lastError = nil
        } catch {
            lastError = "Load failed: \(error)"
        }
    }

    /// Slices every placed object with `profileSelection`'s resolved A1
    /// profile (P3-003) and uploads the real resulting toolpath for
    /// viewport preview (P1-009). Runs the (potentially slow) real engine
    /// pipeline off the main actor so the UI stays responsive; `isSlicing`
    /// drives a progress indicator.
    func slice() {
        guard !objects.isEmpty, !isSlicing else { return }
        isSlicing = true
        var placed: [(mesh: LoadedMesh, transform: simd_float4x4)] = []
        var paintData: [[UInt8]] = []
        var layerHeightRanges: [[LayerHeightRange]] = []
        for object in objects {
            guard let mesh = meshes[object.sourceMeshID] else { continue }
            placed.append((mesh, object.transform.matrix))
            paintData.append(paintStates[object.id]?.serialize() ?? [])
            layerHeightRanges.append(object.layerHeightRanges)
        }
        let selection = profileSelection
        let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gcode").path
        Task.detached { [weak self] in
            do {
                let loader = try BambuProfileLoader()
                let segments = try SlicingJob.slice(
                    objects: placed, loader: loader, selection: selection, outputPath: outputPath,
                    paintData: paintData, layerHeightRanges: layerHeightRanges)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.toolpath = segments
                    self.isSlicing = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.lastError = "Slice failed: \(error)"
                    self.isSlicing = false
                }
            }
        }
    }

    /// Runs a flow-rate calibration slice (pass 1: 0.80→1.20, 0.05 step)
    /// through the real engine without replacing scene geometry or taking a
    /// printer action.
    func calibrate() async {
        guard !isSlicing else { return }
        isSlicing = true
        let resourceURL = CalibrationResources.url(named: "flowrate-test-pass1")
        let selection = profileSelection
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).gcode").path
        do {
            guard let resourceURL else {
                throw SlicingEngineError.sliceFailed("Calibration resource not found")
            }
            let loader = try BambuProfileLoader()
            let request = CalibrationRequest(
                workflow: .flowRate,
                start: 0.8,
                end: 1.2,
                step: 0.05,
                selection: selection
            )
            try CalibrationJob.validate(request, loader: loader, capabilities: .all)
            let configEntries = try SlicingJob.resolvedConfigEntries(loader: loader, selection: selection)
            let generation = try SlicingEngine.generateCalibrationGCode(
                request: request,
                resourceURL: resourceURL,
                configEntries: configEntries,
                outputPath: outputPath
            )
            toolpath = generation.toolpath
            lastCalibration = generation
            lastError = nil
        } catch {
            lastError = "Calibration failed: \(error)"
        }
        isSlicing = false
    }
}
