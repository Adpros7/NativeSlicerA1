# Session State

## Current phase
Phase 1 (Application Foundation) and Phase 2's non-hardware items complete.
Phase 3: P3-001 (feature-parity audit) and P3-002 (all 5 calibration
workflows) complete. Phase 9 P9-007 (macOS deployment-target/zstd fix)
is complete and pushed in `dc2fc9c`.

## Last completed task
P1-012: Implemented G-code toolpath view-mode coloring. Added `ToolpathViewMode`
enum (FeatureType, Height, Feedrate, Temperature, LayerTime, Tool) matching
upstream `EViewType` from `GCodeRenderer`. Extended `ToolpathSegment` with
`feedrate`, `temperature`, `layerDuration`, `extruderID`, `extrusionRole`
fields from the C bridge. Added `color(for:viewMode:)` method with viridis
colormap approximation (piecewise 4th-order polynomial) and discrete
extrusion role colors. Added a "View Mode" picker to the viewport toolbar.
Added `ProjectDocument.toolpathViewMode` @Published property. 16 unit tests
verify per-mode color computation. Full suite: 76 tests passing.

## Current task / progress
P4-001: `nsa1_get_3mf_unit` C-ABI extracts the `unit` attribute from 3MF files (parses XML `<model>` tag), Swift wrapper `SlicingEngine.threeMFUnit`. Full suite: 76 tests passing.
P3-002 complete: all 5 calibration workflows (flow-rate, pressure-advance,
temperature, retraction, max-volumetric-speed) implemented end-to-end.
P4-004: C API (`nsa1_cut_model`) + Swift wrapper (`SlicingEngine.cutModel`) for model splitting along user-specified planes. Returns 0, 1, or 2 sliced `LoadedMesh` objects. C++ uses upstream `Slic3r::ModelObject::cut()`. Swift wrapper accepts `(vertices, indices, matrix)` tuples. Full suite: 76 tests passing.
P1-010 (STL/OBJ/STEP import/export) and P1-011 (print-time/filament
estimation) complete. P1-012 (view-mode coloring) complete.

## Important technical decisions
- **Viridis colormap**: 4th-order polynomial approximation (r, g, b each
  as a function of t and t^3, t^4) matching the 256-entry public-domain
  viridis palette. Clamped to [0,1].
- **Extrusion role colors**: Discrete per-role colors matching upstream
  `Extrusion_Role_Colors`: perimeter=orange, infill=green, support=blue,
  skirt/brim=gray, etc.
- **Tool colors**: 6 distinct hues cycling by extruder ID.

## Uncommitted changes
None.

## Known blockers
None for P1-012. Remaining project-wide blockers unchanged from prior sessions.

## Next recommended action
Pick the next unblocked `TODO.md` task. Candidates:
- P4-004: Cut tool
- P4-010: Auto-orient
- P4-011: Arrange
- P3-004/005: Painting
Or continue through the P4-series geometry work.

## Relevant test/build commands
- `Scripts/build-libslic3r.sh` — one-time/idempotent engine build.
- `swift build` / `swift test` / `swift run NativeSlicerA1`.
- `swift test --filter ToolpathViewModeTests` — 16 color computation tests.
- `swift test --filter CalibrationJobTests` — 15 calibration tests.
- `swift test --filter SlicingJobTests` — 7 slicing tests.
