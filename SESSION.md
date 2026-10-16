# Session State

## Current phase
Phase 1 (Application Foundation) and Phase 2's non-hardware items complete.
Phase 3: P3-001 audit, P3-002 calibration, and P3-005 support painting
complete. Phase 4: P4-001 unit detection, P4-003 (largely via P1-006),
P4-004 cut (engine layer), P4-005 connector presets, P4-010 auto-orient,
P4-011 auto-arrange, and P4-012 support blocker/enforcer painting
complete. Phase 9 P9-007 (macOS deployment-target/zstd fix) is complete
(`dc2fc9c`).

## Last completed task
P4-005: connector presets. `nsa1_make_connector_mesh` wraps the real
engine's `ModelObject::get_connector_mesh` (Plug/Dowel/Snap/Thread x
Prizm/Frustum x 4 shapes -> `its_make_cylinder`/`its_make_cone`/
`its_make_frustum_dowel`/`its_make_snap`/`its_make_thread`), scaled by the
exact transform `apply_cut_connectors` uses, with an `apply_hole_tolerance`
flag reproducing `apply_tolerance`'s additive radius/height widening for
the hole side (CutUtils.cpp). `Sources/NativeSlicerA1/Connectors.swift`:
`ConnectorType`/`Style`/`Shape` enums (raw values match upstream numeric
order), `ConnectorPreset`, `ConnectorMeshGenerator.generate()`.
`Tests/NativeSlicerA1Tests/ConnectorTests.swift`: 6 tests against the real
engine (exact Plug/Prizm cylinder dimensions, linear radius/height
scaling, exact tolerance widening, all 4 types produce real non-empty
geometry including Snap's real bulge past nominal radius verified rather
than asserted away). Full suite: 93 tests passing. Pushed `088176f`.

Before that: P3-005/P4-012 interactive support-paint viewport UI (paint
mode toggle, brush radius/type, ray-cast click/drag painting via
`Raycast.swift`'s Moller-Trumbore intersection), 3MF persistence
(`nsa1_load_3mf_paint`), and per-stroke undo/redo. Pushed `f526e08`.

## IMPORTANT — scope gap discovered for P4-006
P4-006 ("connector customization... interactive placement/deletion in the
Metal viewport; properties editable") depends on P4-005 (done) but **also
implicitly depends on a cut-plane gizmo UI that does not exist yet**.
Checked: `ContentView.swift`/`ProjectDocument.swift` have zero references
to `cutModel`/`CutConnector` — P4-004's prior work was engine-bridge-only
(the C-ABI bug fixes + `SlicingEngineBridge.swift` wrapper + unit tests),
never wired into the UI as an interactive cut-plane tool. TODO.md itself
flagged this originally ("NativeSlicerA1's single largest 0%-implemented
area"). P4-006 cannot be done honestly as "connector placement UI" alone;
it needs, in order:
1. An interactive cut-plane gizmo in the Metal viewport (drag to
   position/orient a plane, like upstream's `GLGizmoCut.cpp`) — this is
   the real missing prerequisite, not currently tracked as its own
   TODO.md line (folded into P4-004's original acceptance criteria, which
   only required the non-UI mesh/topology test, now met).
2. Connector placement on top of that plane (click to add, drag to
   reposition, delete, per-connector property editing panel using the
   new `ConnectorPreset`/`ConnectorMeshGenerator` from P4-005).
3. Color-coded rendering of placed connectors in the Metal view (new
   render pass/instance buffer, reusing the paint-mode raycast
   infrastructure's camera-ray math where useful).
4. Wiring connectors into the actual cut call (`nsa1_cut_model` today
   takes no connector list at all — `NSA1CutRequest` has no connector
   array field) so cutting actually adds negative-volume holes / positive
   dowel volumes, matching upstream's `apply_cut_connectors`/
   `process_connector_cut`.
This is multi-session-sized new gizmo+rendering+bridge work, not a
UI-only polish pass. Per AGENTS.md §1 ("do not attempt to implement the
entire application at once") this should be its own dedicated session,
not rushed to closure in the tail of this one.

## Important technical decisions
- **Connector mesh generator reuses upstream's exact scale math**: unit
  mesh from `get_connector_mesh` times `(radius, radius, height)`, plus
  additive tolerance for the hole side — no reimplementation of connector
  geometry, matches `Model.cpp`/`CutUtils.cpp` exactly.
- **P3-005/P4-012**: `TriangleSelector`-backed C-ABI; paint state owned by
  `ProjectDocument` per object ID (not embedded in the `SceneObject`
  value type); undo/redo via the existing generic `UndoStack` over the
  engine's own serialized snapshots.
- **Prior P4-010/P4-011 fixes**: 5 real root causes fixed in `4564ece`
  (dangling matrix pointer, 3x vertex count, orientation callback, 3x3
  vs 4x4 matrix read, libnest2d sentinel collision). `vendor/` was only
  used for temporary diagnostics, always reverted pristine.

## Uncommitted changes
None.

## Known blockers
None technical. P3-004 (multicolor painting) stays deferred per explicit
TODO.md P4/lowest-priority note. P4-002 manual repair remains conditional
on observing a real mesh-repair need. P4-006/007 need the cut-plane gizmo
UI built first (see scope-gap note above) before connector placement UI
makes sense.

## Next recommended action
Pick one, in order of real unblocked value:
1. Build the interactive cut-plane gizmo in the Metal viewport (the real
   prerequisite for P4-006/007) — drag-to-position plane, "Cut" button
   calling the already-working `SlicingEngine.cutModel`.
2. P4-008/P4-009: multi-plate arrangement + assembly previews (P3
   priority, no blocking gaps, builds on P4-011's working `arrange()`
   bridge).
3. P4-013: modifier meshes (can reuse P3-005's raycast + painting
   gizmo infra once the cut-plane gizmo above exists, since modifier
   mesh placement needs similar interactive placement).
4. P4-014: variable layer height (Z-range UI only, no gizmo dependency —
   could be done independently of the cut-plane gizmo work).
5. P3-004: multicolor/MMU painting — intentionally last (P4 priority).

## Relevant commands
- `swift build` / `swift test` / `swift run NativeSlicerA1`
- `swift test --filter ConnectorTests` — 6 real connector-mesh tests
- `swift test --filter SupportPaintingTests` — 5 real paint engine tests
- `swift test --filter RaycastTests` — viewport hit testing
- `swift test --filter AutoArrangeTests` — 3 orient/arrange tests
- `cd vendor/BambuStudio/build/arm64 && ninja libslic3r libnest2d` — only
  for temporary upstream instrumentation; ALWAYS revert vendor sources
  afterward (`git -C vendor/BambuStudio checkout --`).
