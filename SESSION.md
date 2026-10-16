# Session State

## Current phase
Phase 1 (Application Foundation) and Phase 2's non-hardware items complete.
Phase 3: P3-001 audit, P3-002 calibration, and P3-005 support painting
complete. Phase 4: P4-001 unit detection, P4-003 (largely via P1-006),
P4-004 cut (engine layer + real interactive cut-plane gizmo UI), P4-005
connector presets, P4-006 connector customization, P4-007 connector
reversibility, P4-008 multi-plate arrangement, P4-010 auto-orient,
P4-011 auto-arrange, P4-012 support blocker/enforcer painting, and
P4-014 variable layer height complete. Phase 9 P9-007 is complete.

## Last completed task
P4-008: multi-plate arrangement (batch-job plate grouping — the A1 is
single-bed hardware, so "plate" here is an app-level concept: independent
object subsets, each with its own real auto-arrange/slice/export, not
simultaneous multi-bed hardware). `Plate` (id: `UInt64`, name),
`SceneObject.plateID`, `ProjectDocument.plates`/`activePlateID`/
`objectsOnActivePlate`/`addPlate()`/`removePlate()` (reassigns objects to
the remaining plate, never deletes them) /`autoArrangeActivePlate()`
(real `SlicingEngine.autoArrange`, filtered to the active plate only).
Plate assignment persists through save/load.
`Tests/NativeSlicerA1Tests/MultiPlateTests.swift`: 5 tests. Full suite:
119 tests passing (verified via a full clean rebuild + 5 repeated runs,
after the investigation below).

### IMPORTANT finding: a real, reproduced, bisected toolchain/binary-layout sensitivity
While implementing plate-id 3MF persistence, merely adding an unused
`plateIDs: [UInt64] = []` parameter to `SlicingEngine.storeThreeMF`'s
Swift signature (no behavior change — the parameter was provably dead,
`_ = plateIDs`) made an UNRELATED, already-passing test
(`SupportPaintingTests.testSupportPaintPersistsThroughThreeMF`) fail
deterministically (0/0 support generated instead of >0) when run as
part of the full suite — while remaining 100% green in isolation. This
was rigorously bisected, one change at a time, with full clean rebuilds
and 3-5 repeated full-suite runs at each step (not single-run
conclusions) to rule out flakiness/stale-build artifacts:
- `NSA1SceneObject` growing by a SECOND `uint64_t` field (`plate_id`,
  on top of P4-007's already-safe `cut_group_id`): broke it.
- Moving `plate_id` OUT of `NSA1SceneObject` into a separate C
  parameter on `nsa1_store_3mf` itself: STILL broke it, even with
  `nil`/empty data always passed.
- Adding the dead, unused `plateIDs` Swift parameter to
  `storeThreeMF`'s signature ALONE, data completely unused: STILL
  broke it.
- Reverting `storeThreeMF`'s signature to be byte-identical to its
  known-good committed form, and instead adding plate-id persistence
  as a WHOLLY SEPARATE function (`SlicingEngine.storeThreeMFPlateIDs`
  / `nsa1_append_plate_ids`, called as its own step right after
  `storeThreeMF` succeeds): fully resolved it — 5/5 clean full-suite
  runs plus a final clean-rebuild verification.
This is a genuine, reproducible sensitivity to `storeThreeMF`'s exact
signature/binary layout (root cause not fully understood — plausibly a
Swift/XCTest toolchain or linker-layout interaction, not a logic bug:
the data path was provably inert at every broken step). Documented
in-code at both the `nsa1_store_3mf`/`nsa1_append_plate_ids` C header
declarations and `storeThreeMFPlateIDs`'s Swift doc comment. **Any
future change to `storeThreeMF`'s signature should re-run the full
suite 3-5× (not once) before trusting a clean result**, given how
subtle and full-suite-only this was.

Before that (same session): P4-007 connector reversibility (scene-level
cut undo/redo + cut_id 3MF persistence, discovering the legacy-vs-bbs
3MF format split). Pushed `37928f6`. Before that: P4-004/P4-006
interactive cut-plane gizmo + connector customization, 3 real `cutModel`
bugs fixed. Pushed `a5253bc`.

## Important technical decisions
- **`storeThreeMF`'s signature is now effectively frozen** — new
  per-object 3MF metadata (beyond `cutGroupIDs`/`paintData` already
  there) should be added via a separate `storeThreeMF*`-style follow-up
  call (see `storeThreeMFPlateIDs`'s pattern), not a new parameter on
  `storeThreeMF` itself, until the toolchain sensitivity above is
  actually root-caused.
- **Two different 3MF formats exist in the vendored engine**:
  `Format/3mf.cpp` (legacy, what this bridge uses throughout) vs.
  `Format/bbs_3mf.cpp` (BambuStudio's separate full project format with
  `cut_id`/multi-plate support, NOT used here). P4-007/P4-008 both
  persist their own scalar metadata via small self-contained custom
  3MF archive entries (miniz reader→writer conversion) instead.
- **Plate id is `UInt64`, not `UUID`**: matches `cutGroupID`'s existing
  scalar-persistence convention directly, no mapping layer needed.
- **Connector mesh generator reuses upstream's exact scale math**: unit
  mesh from `get_connector_mesh` times `(radius, radius, height)`, plus
  additive tolerance for the hole side.
- **Connectors are baked via real CGAL Boolean**, not a parallel
  modifier-volume system (the one-mesh-per-object C-ABI can't carry
  BambuStudio's full volume/modifier graph).
- **Cut-plane default normal is world +Z**: matches the slicing engine's
  own height axis, independent of the viewport camera's Y-up orbit.
- **P3-005/P4-012**: `TriangleSelector`-backed C-ABI; paint state owned by
  `ProjectDocument` per object ID; undo/redo via the existing generic
  `UndoStack`.
- **Prior P4-010/P4-011 fixes**: 5 real root causes fixed in `4564ece`.
  `vendor/` was only used for temporary diagnostics, always reverted
  pristine — including this session's `bbs_3mf.cpp` debug instrumentation
  while tracing the cut_id architecture question (fully reverted).

## Uncommitted changes
P4-008 (multi-plate grouping + the `storeThreeMFPlateIDs` toolchain-
sensitivity fix) is implemented and fully tested (119/119, verified via
clean rebuild + 5 repeated full-suite runs) but not yet committed/pushed
as of this update — do that next.

## Known blockers
None technical. P3-004 (multicolor painting) stays deferred per explicit
TODO.md P4/lowest-priority note. P4-002 manual repair remains conditional
on observing a real mesh-repair need.

## Next recommended action
1. Commit + push P4-008 (see Uncommitted changes above).
2. P4-009: assembly previews — depends on P4-008 (now done). Upstream:
   `GUI/Plater.cpp` plate/object preview rendering; low independent
   value, consider whether it's worth a dedicated pass vs folding into
   general viewport polish.
3. P4-013: modifier meshes (can reuse the raycast + cut-plane gizmo infra).
4. P3-004: multicolor/MMU painting — intentionally last (P4 priority).
5. Minor pre-existing cleanup opportunity noticed but out of scope this
   session: `SlicingEngine.autoArrange`'s `UnsafePointer(meshData.vertices)`/
   `UnsafePointer(meshData.indices)` construction is the same class of
   dangling-temporary-pointer compiler warning seen elsewhere in this
   file — not yet reproduced as an actual failure, but worth an eventual
   fix using `withNSA1SceneObjects` like other call sites already do.

## Relevant commands
- `swift build` / `swift test` / `swift run NativeSlicerA1`
- `swift test --filter MultiPlateTests` — 5 real multi-plate tests
- `swift test --filter CutModelTests` — 7 real cut/connector-boolean tests
- `swift test --filter CutPlaneTests` — connector placement transform test
- `swift test --filter ProjectDocumentCutTests` — 9 real cut/connector/undo tests
- `swift test --filter CutGroupIDPersistenceTests` — 2 real cut_id/3MF tests
- `swift test --filter ConnectorTests` — 6 real connector-mesh tests
- `swift test --filter VariableLayerHeightTests` — 2 real layer-height-range tests
- `swift test --filter SupportPaintingTests` — 5 real paint engine tests
- `swift test --filter RaycastTests` — viewport hit testing + ray-plane
- `swift test --filter AutoArrangeTests` — 3 orient/arrange tests
- `cd vendor/BambuStudio/build/arm64 && ninja libslic3r libnest2d` — only
  for temporary upstream instrumentation; ALWAYS revert vendor sources
  afterward (`git -C vendor/BambuStudio checkout --`).
- When touching `storeThreeMF`'s signature: run the FULL suite 3-5×
  (`rm -rf .build && swift build && for i in 1 2 3; do swift test; done`)
  before trusting a clean result — see the toolchain-sensitivity finding
  above.
- Manual GUI smoke test: launch via a real `.app` bundle (the raw
  `.build/out/Products/Debug/NativeSlicerA1` executable run directly is
  NOT Dock-registered and exits when its launching terminal session
  ends) — wrap it: `mkdir -p /tmp/NativeSlicerA1.app/Contents/MacOS`,
  write a minimal `Info.plist`, symlink the built executable in, then
  `open -n /tmp/NativeSlicerA1.app`.
