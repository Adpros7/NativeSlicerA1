# Session State

## Current phase
Phase 1 (Application Foundation) and Phase 2's non-hardware items complete.
Phase 3: P3-001 (feature-parity audit) and P3-002 (all 5 calibration
workflows) complete. Phase 9 P9-007 (macOS deployment-target/zstd fix)
is complete and pushed in `dc2fc9c`. Phase 4: P4-001, P4-004, P4-010,
P4-011 complete.

## Last completed task
P4-011 (auto-arrange) + P4-010 (auto-orient) fixes. Root-caused and fixed
5 real bugs (not reimplementations — all in the real engine-call path):
1. `nsa1_auto_orient`: `OrientParams.progressind` defaults to an empty
   `std::function` that upstream `_orient()` calls unconditionally (no
   null check) → `std::bad_function_call`. Fixed with a no-op callback.
2. `nsa1_auto_orient`: `OrientMesh::rotation_matrix` is a 3x3
   `Eigen::Matrix3d` (9 doubles), not 4x4 — was reading 16 doubles out
   of bounds. Fixed: embed the 3x3 into a proper 4x4 homogeneous matrix.
3. `nsa1_auto_arrange`/`cutModel` (Swift): `NSA1SceneObject.vertex_count`
   was set to the flat float count (3x too large). Fixed to `count/3`,
   matching the established convention used elsewhere in the file.
4. `nsa1_auto_arrange`/`cutModel` (Swift): `NSA1SceneObject.matrix16`
   pointed into a freshly-created `[Double]` local gone out of scope
   before the C call executed (dangling pointer, read back as zeros).
   Fixed with manually-allocated, explicitly-freed storage kept alive
   for the whole call.
5. `nsa1_auto_arrange`: `ArrangePolygon::bed_idx` defaults to
   `UNARRANGED` (-1), numerically identical to libnest2d's
   `BIN_ID_UNFIT` sentinel — the packer's per-item loop skips any item
   whose `binId()` already equals that sentinel *before* attempting to
   place it, so every item was silently skipped. Fixed: explicitly set
   `bed_idx=0` before `arrange()`, matching upstream's own
   `ModelArrange.cpp::get_arrange_poly()`.
Also found (and routed around) that `TriangleMesh::convex_hull()` (2D)
returns an empty `Polygon` in this vendored build — calls the
lower-level `Slic3r::Geometry::convex_hull()` directly instead (same
documented algorithm).
Root-caused via direct inspection of the real linked vendored library:
lldb breakpoints on `__cxa_throw` to get real backtraces into the
prebuilt library, plus incremental `ninja libslic3r`/`ninja libnest2d`
rebuilds with temporary `printf` diagnostics patched directly into
`vendor/BambuStudio/src/libslic3r/Arrange.cpp` and
`vendor/BambuStudio/src/libnest2d/include/libnest2d/selections/firstfit.hpp`
(reverted to pristine upstream afterward, confirmed via `git diff`).
Added `Tests/NativeSlicerA1Tests/AutoArrangeTests.swift`: 3 tests against
the real `arrangement::arrange()`/`orientation::orient()` engine calls.
Full suite: 79 tests passing. Pushed in `4564ece`.

## Current task / progress
P4-001 (`nsa1_get_3mf_unit`), P4-004 (`nsa1_cut_model`), P4-010
(`nsa1_auto_orient`), P4-011 (`nsa1_auto_arrange`) all complete with C
API + Swift wrapper + passing tests against the real engine. P1-010/011
(STL/OBJ/STEP import-export, print-time/filament estimation) and P1-012
(view-mode coloring) complete from earlier sessions.

## Important technical decisions
- **Vendored-library bugs are real, not misreading**: confirmed 5
  distinct defects in the actually-linked `BambuStudio` commit's
  `Orient.cpp`/`Arrange.cpp`/`firstfit.hpp` by rebuilding those exact
  object files with diagnostics and observing real runtime behavior —
  not guessed from the `.research` source snapshot alone (same commit,
  but static reading repeatedly missed runtime-only facts like which
  sentinel values collide).
- **Fix at the call site, not by patching vendor/**: all 5 fixes live in
  `Sources/CSlic3rBridge/CSlic3rBridge.cpp`/`SlicingEngineBridge.swift`
  (supplying required callbacks, correct struct field values, pointer
  lifetimes) rather than patching the vendored AGPLv3 source in place —
  keeps upstream modifications isolated per AGENTS.md §4.
- **2D hull via `Geometry::convex_hull()` not `TriangleMesh::convex_hull()`**:
  the member-function wrapper is broken in this vendored build; the
  lower-level namespace function it's documented to call is used
  directly instead, verified against real STL geometry (toolpath/hull
  points match the known real part size).

## Uncommitted changes
None.

## Known blockers
None. Remaining project-wide blockers unchanged from prior sessions.

## Next recommended action
Pick the next unblocked `TODO.md` task. Candidates:
- P3-004: Support/material painting (`TriangleSelector`-style gizmo)
- P3-005: Connector generation between objects (depends on P4-004, now
  unblocked)
- P4-002: Manual mesh repair (needs a concrete observed need first)
- P4-005/006/007: Connector presets/customization/reversibility (depend
  on P4-004, now unblocked)
- P4-008/009: Multi-plate arrangement + assembly previews
- P4-012: Support blocker/enforcer painting (shares gizmo infra with
  P3-004/005 — consider implementing once, sharing between both)

## Relevant test/build commands
- `Scripts/build-libslic3r.sh` — one-time/idempotent engine build.
- `swift build` / `swift test` / `swift run NativeSlicerA1`.
- `swift test --filter AutoArrangeTests` — 3 auto-orient/arrange tests.
- `swift test --filter ToolpathViewModeTests` — 16 color computation tests.
- `swift test --filter CalibrationJobTests` — calibration tests.
- `swift test --filter SlicingJobTests` — slicing tests.
- `cd vendor/BambuStudio/build/arm64 && ninja libslic3r libnest2d` —
  incremental rebuild of just these two targets after a vendored-source
  change (e.g. temporary debug patches), without rebuilding all ~25
  deps. ALWAYS `git checkout --` any temporary vendored-source patches
  before finishing — `vendor/` modifications must never be committed.
