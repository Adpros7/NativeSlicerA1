# Session State

## Current phase
Phase 1 (Application Foundation) and Phase 2's non-hardware items complete.
Phase 3: P3-001 audit, P3-002 calibration, and P3-005 support painting
complete. Phase 4: P4-001 unit detection, P4-004 cut, P4-010 auto-orient,
P4-011 auto-arrange, and P4-012 support blocker/enforcer painting complete.
Phase 9 P9-007 (macOS deployment-target/zstd fix) is complete (`dc2fc9c`).

## Last completed task
P3-005 / P4-012: full real support-paint blocker/enforcer workflow.

- **Native engine bridge:** `nsa1_paint_create` / `nsa1_paint_sphere` /
  `nsa1_paint_serialize` / `nsa1_paint_deserialize` / free functions wrap
  upstream `Slic3r::TriangleSelector`; opaque serialized paint data is
  attached to `NSA1SceneObject` and deserialized into the real
  `ModelVolume::supported_facets` before `Print::apply()`.
- **Real engine behavior:** support generation consumes the annotations via
  upstream `SupportMaterial.cpp` / `SupportAnnotations` /
  `project_and_append_custom_facets`; no Swift support geometry or fake
  G-code logic was introduced.
- **Viewport UI:** toolbar has Paint Support mode, Enforcer/Blocker choice,
  1–20mm brush radius, paint undo/redo. In paint mode mouse click/drag
  unprojects through the real camera, transforms the ray into selected mesh
  local coordinates, Möller–Trumbore raycasts the triangle mesh, then paints
  a real TriangleSelector sphere brush at the actual hit point. Orbit remains
  normal outside paint mode.
- **Persistence:** painted `FacetsAnnotation` data is saved by the upstream
  3MF writer and restored after load via `nsa1_load_3mf_paint`; native paint
  state has snapshot undo/redo without mutating source mesh geometry.
- **Verification:** `SupportPaintingTests` proves unpainted flush-bed cube
  produces zero support; enforcer adds real roles 14/15 support toolpath;
  blocker overwrites it back to zero; saved 3MF reload retains the paint;
  undo/redo returns the real toolpath to zero/enforced states. `RaycastTests`
  proves hit/miss behavior. Full suite: 87 tests passing.

Also corrected P1-012's pre-existing raw `ExtrusionRole` mapping defect:
bridge emits the actual `ExtrusionEntity.hpp` enum (support=14/interface=15),
while docs/color table incorrectly used a made-up 0–10 mapping. Updated the
doc, exact upstream `BaseRenderer::Extrusion_Role_Colors` mapping, and
ToolpathViewMode tests.

## Current task / progress
No uncommitted changes after committing this task. P3-004 multicolor painting
remains deliberately deferred: TODO.md calls it P4/lowest-value Phase 3 work
and P3-005/P4-012 shared infrastructure is now complete.

## Important technical decisions
- **Upstream selector, never custom selection logic:** C++ owns painting via
  `TriangleSelector`; Swift stores opaque engine serialization bytes. This
  keeps painting semantics, subdivision, and support projection exactly in
  the mature upstream path.
- **Non-destructive geometry:** paint sessions own copied mesh data; scene
  `LoadedMesh`/source model is never edited. All transforms remain separate.
- **Lifecycle:** `ProjectDocument` owns paint sessions per `SceneObject` ID,
  clears them on removal/load, serializes them before detached slice work,
  and updates the native selector state on undo/redo.
- **Prior P4-010/P4-011 fix:** P4 auto-orient/arrange had 5 real root causes
  fixed in `4564ece`, including a dangling matrix pointer, 3× vertex count,
  orientation callback, 3x3→4x4 out-of-bounds read, and libnest2d sentinel
  collision. Source `vendor/` was used only for temporary diagnostics and
  reverted pristine.

## Uncommitted changes
None after the next commit.

## Known blockers
None technical. P3-004 stays deferred per explicit TODO priority. P4-002
manual repair remains conditional on observing a real mesh-repair need.

## Next recommended action
- P4-005: connector presets (depends on complete P4-004 cut, now unblocked)
- P4-006 / P4-007: connector customization / reversibility
- P4-008 / P4-009: multi-plate arrangement / assembly previews
- P4-013: modifier meshes (can reuse P3-005 raycast + painting UI)
- P4-014: variable layer height
- P3-004: multicolor/MMU painting — intentionally last (P4 priority).

## Relevant commands
- `swift build` / `swift test` / `swift run NativeSlicerA1`
- `swift test --filter SupportPaintingTests` — 5 real paint engine tests
- `swift test --filter RaycastTests` — viewport hit testing
- `swift test --filter AutoArrangeTests` — 3 orient/arrange tests
- `swift test --filter ToolpathViewModeTests` — 17 exact color tests
- `cd vendor/BambuStudio/build/arm64 && ninja libslic3r libnest2d` — only for
  temporary upstream instrumentation; ALWAYS revert vendor sources afterward.
