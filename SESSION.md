# Session State

## Current phase
Phase 1 (Application Foundation) and Phase 2's non-hardware items complete.
Phase 3: P3-001 audit, P3-002 calibration, and P3-005 support painting
complete. Phase 4: P4-001 unit detection, P4-003 (largely via P1-006),
P4-004 cut (engine layer + real interactive cut-plane gizmo UI), P4-005
connector presets, P4-006 connector customization, P4-007 connector
reversibility, P4-010 auto-orient, P4-011 auto-arrange, P4-012 support
blocker/enforcer painting, and P4-014 variable layer height complete.
Phase 9 P9-007 (macOS deployment-target/zstd fix) is complete (`dc2fc9c`).

## Last completed task
P4-007: connector reversibility, two real parts per TODO.md's own spec:

1. **Scene-composition undo for cuts**, reusing the existing `UndoStack`
   generic (not a parallel mechanism): `ProjectDocument.cutHistory:
   UndoStack<[SceneObject]>?`, `canUndoCut`/`canRedoCut`/`undoCut()`/
   `redoCut()`. `performCut()` snapshots `objects` before mutating and
   pushes the post-cut state after. `SceneObject` gained a custom
   `Equatable` (compares observable id/mesh/transform/ranges/cutGroupID,
   not `transformHistory`'s internal undo depth) so `[SceneObject]` can be
   the `UndoStack`'s `State`. Required no longer deleting a cut object's
   mesh from `meshes` even when briefly unreferenced — undo needs it back
   (an orphaned `LoadedMesh` is an accepted bounded cost, not a parallel
   storage mechanism).
2. **`cut_id` that survives 3MF save/reload** — real architecture
   discovery along the way: this bridge's `nsa1_store_3mf`/
   `nsa1_load_3mf_mesh`/etc. call `Slic3r::store_3mf`/`load_3mf`
   (`Format/3mf.cpp`), the LEGACY plain-3MF reader/writer — NOT
   `Format/bbs_3mf.cpp`'s separate `_BBS_3MF_Exporter`/`_Importer`
   classes, which are the ONLY ones with real `ModelObject::cut_id`
   persistence (`Metadata/cut_information.xml`). Confirmed via direct
   experimentation (set `cut_id` before `store_3mf`, round-tripped
   through `load_3mf`, got nothing back) before spending more time on
   that path. Implemented a small self-contained custom archive entry
   instead (`Metadata/NSA1_CutGroups.txt`, `index=value` lines) appended
   to the already-written 3mf via miniz's documented reader-to-writer
   archive conversion (`mz_zip_writer_init_from_reader`, same
   `miniz_extension.hpp`/pattern `nsa1_load_3mf_config` already uses to
   read a custom entry) — doesn't touch `ModelObject::cut_id` or
   `bbs_3mf.cpp` at all, avoiding a large, risky swap of the already-
   tested, working 3MF pipeline for one feature. `SceneObject.cutGroupID:
   UInt64?` (nonzero shares across every part from the same
   `performCut()`), threaded through `storeThreeMF`'s `cutGroupIDs` /
   `SlicingEngine.loadThreeMFCutGroupID` / `ProjectDocument.save`/`load`.

`Tests/NativeSlicerA1Tests/ProjectDocumentCutTests.swift` gained 2 (undo/
redo round trip restores the exact original object incl. its mesh; cut
lineage survives a real `save`→`load` round trip). New
`Tests/NativeSlicerA1Tests/CutGroupIDPersistenceTests.swift`: 2 (raw
bridge-level round trip; uncut objects load as `nil`). Full suite: 114
tests passing.

Before that (same session): P4-004/P4-006 — interactive cut-plane gizmo
(the real missing P4-006 prerequisite) + connector customization on top
of it, plus 3 real `cutModel`/`nsa1_cut_model` bugs found and fixed while
writing its first-ever test coverage (dropped/double-applied instance
transform, a dangling-pointer double-free, and a wasteful/incorrect
double `cut()` call for the both-halves case). Pushed `a5253bc`.

## Important technical decisions
- **Two different 3MF formats exist in the vendored engine**:
  `Format/3mf.cpp` (legacy, what this bridge uses throughout — P1-007,
  P3-003, P3-005 paint, P4-014 layer ranges all go through it) vs.
  `Format/bbs_3mf.cpp` (BambuStudio's separate full project format with
  `cut_id`/multi-plate/assembly support, NOT used here). Any future
  feature that assumes "the real engine's project format already
  handles X" must verify which of the two is actually reachable through
  `nsa1_store_3mf`/`nsa1_load_3mf_mesh` before relying on it — don't
  assume upstream's own write path is live just because the code exists
  in the vendored tree.
- **Custom 3MF archive entries via miniz's reader→writer conversion**:
  `mz_zip_writer_init_from_reader(&archive, path)` requires the reader
  side to come from `mz_zip_reader_init_file` (path-based), not
  `Slic3r::open_zip_reader` (which uses `FILE*`-based
  `mz_zip_reader_init_cfile` — these don't interoperate for the
  reader→writer conversion; real bug found and fixed during this
  session's own new code, not shipped).
- **Connector mesh generator reuses upstream's exact scale math**: unit
  mesh from `get_connector_mesh` times `(radius, radius, height)`, plus
  additive tolerance for the hole side — no reimplementation of connector
  geometry, matches `Model.cpp`/`CutUtils.cpp` exactly.
- **Connectors are baked via real CGAL Boolean, not a parallel modifier-
  volume system**: `NSA1SceneObject`'s one-mesh-per-object C-ABI contract
  can't carry BambuStudio's full volume/modifier graph, so connector
  results are flattened into a single real Boolean-combined mesh per cut
  half rather than attempting to preserve separate volumes across the
  Swift boundary.
- **Cut-plane default normal is world +Z**: matches the slicing engine's
  own height axis (same convention `LayerHeightRange`/`cutModel`'s plane
  points already use), independent of the viewport camera's separate
  Y-up orbit parametrization.
- **P3-005/P4-012**: `TriangleSelector`-backed C-ABI; paint state owned by
  `ProjectDocument` per object ID; undo/redo via the existing generic
  `UndoStack` over the engine's own serialized snapshots.
- **Prior P4-010/P4-011 fixes**: 5 real root causes fixed in `4564ece`.
  `vendor/` was only used for temporary diagnostics, always reverted
  pristine — including this session's several rounds of `bbs_3mf.cpp`
  debug instrumentation while tracing the cut_id architecture question.

## Uncommitted changes
P4-007 (scene-level cut undo/redo + cut_id/cutGroupID 3MF persistence) is
implemented and fully tested (114/114) but not yet committed/pushed as of
this update — do that next.

## Known blockers
None technical. P3-004 (multicolor painting) stays deferred per explicit
TODO.md P4/lowest-priority note. P4-002 manual repair remains conditional
on observing a real mesh-repair need.

## Next recommended action
1. Commit + push P4-007 (see Uncommitted changes above).
2. P4-008/P4-009: multi-plate arrangement + assembly previews — next in
   TODO.md's own stated order now that P4-004..007 are all complete.
3. P4-013: modifier meshes (can reuse the raycast + cut-plane gizmo infra).
4. P3-004: multicolor/MMU painting — intentionally last (P4 priority).
5. Minor pre-existing cleanup opportunity noticed but out of scope this
   session: `SlicingEngine.autoArrange`'s `UnsafePointer(meshData.vertices)`/
   `UnsafePointer(meshData.indices)` construction is the same class of
   dangling-temporary-pointer risk as the bug fixed in `cutModel` this
   session — not yet reproduced as an actual failure, but worth an
   eventual test + fix pass using `withNSA1SceneObjects` like the other
   call sites already do.

## Relevant commands
- `swift build` / `swift test` / `swift run NativeSlicerA1`
- `swift test --filter CutModelTests` — 7 real cut/connector-boolean tests
- `swift test --filter CutPlaneTests` — connector placement transform test
- `swift test --filter ProjectDocumentCutTests` — 9 real document-level
  cut/connector/undo state-machine tests
- `swift test --filter CutGroupIDPersistenceTests` — 2 real cut_id/3MF tests
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
