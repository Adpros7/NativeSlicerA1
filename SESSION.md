# Session State

## Current phase
Phase 1 (Application Foundation) and Phase 2's non-hardware items complete.
Phase 3: P3-001 audit, P3-002 calibration, and P3-005 support painting
complete. Phase 4: P4-001 unit detection, P4-003 (largely via P1-006),
P4-004 cut (engine layer + real interactive cut-plane gizmo UI), P4-005
connector presets, P4-006 connector customization, P4-010 auto-orient,
P4-011 auto-arrange, P4-012 support blocker/enforcer painting, and
P4-014 variable layer height complete. Phase 9 P9-007 (macOS
deployment-target/zstd fix) is complete (`dc2fc9c`).

## Last completed task
P4-006: connector customization (interactive placement/deletion in the
Metal viewport, editable properties, real cut-pipeline integration),
built on top of the interactive cut-plane gizmo this session added as
P4-006's real missing prerequisite (see prior session's scope-gap note,
now resolved).

Along the way, exercising `SlicingEngine.cutModel`/`nsa1_cut_model` for
the first time ever (it had zero test coverage despite being marked
done) found and fixed 3 real bugs:
1. `scene_object_from_model_object` always returned `matrix16: nullptr`,
   dropping the real post-cut instance placement, AND separately used
   `obj.mesh()` (which already bakes in the instance transform) while
   trying to also return that transform — double-applying it. Fixed:
   `obj.raw_mesh()` (volume transform only) + return the instance
   transform exactly once via `matrix16`.
2. The same function then called `nsa1_free_mesh(mesh_data)` after
   handing `mesh_data`'s arrays to the returned struct — a real
   double-free/dangling-pointer bug, reproduced as an actual
   `malloc: *** error ... pointer being freed was not allocated` abort.
3. `cut_mode: both` called `ModelObject::cut()` TWICE (once per flag)
   instead of once with combined `KeepUpper|KeepLower` — wasteful and
   skipped `cut_id` assignment. Fixed to a single combined-attribute call
   matching upstream's own GUI pattern.
`Tests/NativeSlicerA1Tests/CutModelTests.swift`: 6 tests (volume
preservation, per-half individual volume, world-space size, translation-
equivariance of the real instance transform — this specific test is what
would have caught bugs 1 and 3 above — and degenerate-plane handling).
Discovered real upstream Cut tool behavior along the way: cut pieces do
NOT preserve their exact pre-cut world position (`ModelObject::cut`'s
`reset_instance_transformation`/`center_around_origin` recenters each
piece independently, matching `Plater::load_model_objects`'s per-object
`ensure_on_bed()` — pieces are meant to become independent printable
objects, not stay visually reassembled). Tests assert translation-
independent invariants accordingly, not a wrong absolute-position
assumption.

**Cut-plane gizmo** (`CutPlane.swift`): world-space center + tiltX/tiltY
(matching the real engine's plane-point convention, default normal =
world +Z matching the slicing/G-code height axis, independent of the
viewport camera's separate Y-up rendering convention). Generates the
real 4 `planePoints` `cutModel` consumes directly, plus wireframe line
segments drawn via the existing toolpath line-list Metal pipeline (no
new pipeline state). `ProjectDocument.worldBoundingBox(for:)`,
`cutPlaneMode`/`cutPlane`/`cutKeepMode` state, `beginCutPlane()` auto-
centers on the real selected object's bounding box, `performCut()` calls
the real `cutModel` and replaces the selected object with the real
result(s) (source object consumed, matching upstream — not kept
alongside its own pieces; P4-007 will add undo for this). Click/drag in
the viewport (mirrors the existing paint-mode routing) repositions the
plane via a real mesh raycast. Toolbar: Cut Plane toggle, height/tilt
sliders, Both/Lower/Upper picker, Cut button.

**Connector customization** (this task, on top of the gizmo):
`CutConnectorPlacement` (world position + `ConnectorPreset`) lives on
`ProjectDocument.cutConnectors`, pending-only until a real cut — source
mesh/geometry stays untouched while editing. `CutPlane.connectorTransform`
places the real upstream-generated connector mesh (local +Z aligned to
plane normal, symmetric across the clicked point) for an accurate Metal
preview (`MetalRenderer.updateBuffer` redraws the real generated mesh on
every preset edit; selected connector renders in a distinct color).
`rayPlaneIntersection` (new `Raycast.swift` helper, tested) places
connectors by clicking the visible plane itself (stable while tilting),
not the object surface. Toolbar: Place Connector toggle, per-connector
picker, Type/Radius/Depth controls, Delete button.

**Real cut-pipeline integration** (`cut_connector_mesh`/
`scene_object_from_baked_mesh` in `CSlic3rBridge.cpp`): each placed
connector is baked into the real returned cut geometry using upstream's
actual `MeshBoolean::cgal` engine — the toleranced hole mesh is
subtracted from the upper piece, the exact peg mesh is unioned into the
lower piece, using the exact same `ModelObject::get_connector_mesh`
generator P4-005 already wraps. `NSA1CutRequest` gained an optional
`connectors`/`connector_count` array (`NSA1CutConnector`); when any
connector is present, `cut_mode` is forced to both-halves (a connector
is a mating pair — returning only one side would silently drop either
the peg or the hole). Required `its_merge_vertices` on the transient cut-
result mesh copies before the Boolean call (binary-STL-style meshes with
per-facet-duplicated vertices are valid non-destructive input, but CGAL's
Boolean needs a connected indexed surface; this never touches the source
model). `CutModelTests.testPlugConnectorBakesTolerancedHoleAndPegIntoCutResults`
and `ProjectDocumentCutTests.testPerformCutBakesPlacedConnectorIntoResultMeshes`
prove the real mesh volume actually changes (not a config echo / preview-
only state) through both the raw bridge call and the full document state
machine a user drives via the toolbar.

Full suite: 110 tests passing.

## Important technical decisions
- **Connector mesh generator reuses upstream's exact scale math**: unit
  mesh from `get_connector_mesh` times `(radius, radius, height)`, plus
  additive tolerance for the hole side — no reimplementation of connector
  geometry, matches `Model.cpp`/`CutUtils.cpp` exactly.
- **Connectors are baked via real CGAL Boolean, not a parallel modifier-
  volume system**: `NSA1SceneObject`'s one-mesh-per-object C-ABI contract
  can't carry BambuStudio's full volume/modifier graph, so connector
  results are flattened into a single real Boolean-combined mesh per cut
  half rather than attempting to preserve separate volumes across the
  Swift boundary. Scoped explicitly to P4-006; P4-007's `cut_id`/undo
  work is unaffected since it operates on the `ProjectDocument` object
  list, not the mesh internals.
- **Cut-plane default normal is world +Z**: matches the slicing engine's
  own height axis (same convention `LayerHeightRange`/`cutModel`'s plane
  points already use), independent of the viewport camera's separate
  Y-up orbit parametrization — verified via `Camera.swift`'s spherical
  coordinate formula before relying on it.
- **P3-005/P4-012**: `TriangleSelector`-backed C-ABI; paint state owned by
  `ProjectDocument` per object ID (not embedded in the `SceneObject`
  value type); undo/redo via the existing generic `UndoStack` over the
  engine's own serialized snapshots.
- **Prior P4-010/P4-011 fixes**: 5 real root causes fixed in `4564ece`
  (dangling matrix pointer, 3x vertex count, orientation callback, 3x3
  vs 4x4 matrix read, libnest2d sentinel collision). `vendor/` was only
  used for temporary diagnostics, always reverted pristine.

## Uncommitted changes
Cut-plane gizmo + P4-006 connector customization work is implemented and
fully tested (110/110) but not yet committed/pushed as of this update —
do that next, then mark P4-006 `[x]` in TODO.md (already done in this
edit) and push.

## Known blockers
None technical. P3-004 (multicolor painting) stays deferred per explicit
TODO.md P4/lowest-priority note. P4-002 manual repair remains conditional
on observing a real mesh-repair need.

## Next recommended action
1. Commit + push the cut-plane gizmo + P4-006 connector work (see
   Uncommitted changes above).
2. P4-007: connector reversibility — integrate cuts into the existing
   `UndoStack` pattern (don't build a parallel history mechanism) plus a
   `cut_id` that survives 3MF save/reload. Note: `performCut()` currently
   removes the source object and adds results with no undo at all: this
   is the concrete gap P4-007 closes.
3. P4-008/P4-009: multi-plate arrangement + assembly previews (P3
   priority, no blocking gaps, builds on P4-011's working `arrange()`
   bridge).
4. P4-013: modifier meshes (can reuse the raycast + cut-plane gizmo
   infra now that it exists).
5. P3-004: multicolor/MMU painting — intentionally last (P4 priority).

## Relevant commands
- `swift build` / `swift test` / `swift run NativeSlicerA1`
- `swift test --filter CutModelTests` — 7 real cut/connector-boolean tests
- `swift test --filter CutPlaneTests` — connector placement transform test
- `swift test --filter ProjectDocumentCutTests` — 6 real document-level
  cut/connector state-machine tests (toggle, place, edit, delete, cut)
- `swift test --filter ConnectorTests` — 6 real connector-mesh tests
- `swift test --filter VariableLayerHeightTests` — 2 real layer-height-range tests
- `swift test --filter SupportPaintingTests` — 5 real paint engine tests
- `swift test --filter RaycastTests` — viewport hit testing + ray-plane
- `swift test --filter AutoArrangeTests` — 3 orient/arrange tests
- `cd vendor/BambuStudio/build/arm64 && ninja libslic3r libnest2d` — only
  for temporary upstream instrumentation; ALWAYS revert vendor sources
  afterward (`git -C vendor/BambuStudio checkout --`).
- Manual GUI smoke test: launch via a real `.app` bundle (the raw
  `.build/out/Products/Debug/NativeSlicerA1` executable run directly is
  NOT Dock-registered and exits when its launching terminal session
  ends) — wrap it: `mkdir -p /tmp/NativeSlicerA1.app/Contents/MacOS`,
  write a minimal `Info.plist`, symlink the built executable in, then
  `open -n /tmp/NativeSlicerA1.app`.
