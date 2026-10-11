# Session State

## Current phase
Phase 1 (Application Foundation) and Phase 2's non-hardware items complete.
Phase 3: P3-001 (source-cited feature-parity audit) complete this session;
P3-002 (calibration workflows) is next. Phase 9 P9-007 (macOS
deployment-target/zstd fix) is complete and pushed in `dc2fc9c`.

## Last completed task
P3-001: Replaced the former unsourced 274-row P0-011 draft with a
source-cited parity audit (`FEATURE_PARITY.md`) against the exact upstream
pins this project uses: BambuStudio `v02.08.04.61` (`f5e51a2`) and
OrcaSlicer `v2.4.2` (`8500fcd`). Six independent source-research passes
covered all user-requested categories: import/export, transforms,
cut/connectors, orientation/arrangement, supports/modifiers/multi-plate,
settings/advanced slicing, multicolor/AMS/purge/sequential printing,
G-code/viewer, calibration, connectivity/monitoring/camera, MakerWorld,
persistence/compatibility, error recovery, performance, and accessibility.
Every documented upstream claim is backed by a file:line citation in the
pinned local source, with closed-source Bambu networking/plugin behavior
explicitly marked as unavailable instead of fabricated. The audit
corrected false binary "unsupported" claims where P3-003's complete
profile closure already reaches the real engine (e.g. supports, ironing,
Arachne, contour compensation) but UI overrides are absent. It also
protected the explicitly requested calibration scope: all five workflows
(flow, pressure advance, temperature, retraction, max volumetric speed)
remain P3-002 work in the requested order; PA generation is gated on
actual printer/firmware compatibility rather than silently dropped.

`TODO.md` now records independently implementable tasks with sources and
tests: format I/O + estimates/view modes (P1-010..012), detailed
calibration acceptance criteria, cut/connector/arrange support work
(P4-004..014), and MakerWorld's proprietary-auth risk. P0-011/P3-001/P3-007
are complete. The connectivity-specific source audit is retained in
`RESEARCH-P0-011-CONNECTIVITY.md`.

## Current task / progress
P3-002 flow-rate calibration is complete: a native `Calibration…` SwiftUI
sheet labels the fixed pass-1 range and active printer/process/filament;
Generate invokes the real local engine path, updates the existing Metal
toolpath, retains blocks/output path in `lastCalibration`, preserves scene
objects, and has no upload/send/print/MQTT path. XCTest verifies resource
availability, validation/capability errors, bridge missing-resource errors,
real engine output, and document non-destructive behavior; full suite:
52 tests passing. Remaining P3-002 workflows: pressure advance,
temperature tower, retraction, max volumetric speed, then unified result
application/persistence and a final independent review.

## Important technical decisions
- **License**: AGPLv3 (RESEARCH.md P0-004) — required to reuse `libslic3r`.
- **Engine source**: `Scripts/build-libslic3r.sh` clones BambuStudio
  (pinned stable tag `v02.08.04.61`, not `master`) into `vendor/BambuStudio`
  (gitignored), builds its ~25 third-party deps + `libslic3r` itself via
  CMake/Ninja (idempotent, ~2-10 min depending on cache state), plus a
  small `nsa1_libslic3r_leak_shim` static lib working around an upstream
  architecture leak (libslic3r's `LogSink.cpp` calls into GUI-layer
  `Http`/`BBL_Encrypt` classes it shouldn't depend on).
- **Swift↔engine bridge**: C-ABI (`Sources/CSlic3rBridge`), not Swift's
  native C++ interop — libslic3r's Boost/Eigen/CGAL-heavy headers don't
  import cleanly. `Package.swift`'s `linkerSettings` hardcode the ~88
  static-lib/framework link line, computed once from CMake's own resolved
  link graph (don't hand-enumerate this dependency graph again if it
  needs to change — rebuild a throwaway CMake executable target linking
  `libslic3r` and read `ninja -t commands <target>` for the real line).
  **Gotcha**: `NANOSVG_IMPLEMENTATION` must be `#define`d and `#include`d
  before any libslic3r header, or its include guard blocks the later
  definition if something transitively includes `nanosvg.h` first.
- **Build system**: SwiftPM (`Package.swift`), no `.xcodeproj`.
- **Viewport/persistence**: `ProjectDocument` owns source meshes plus
  non-destructive `SceneObject` transforms. It writes/reads an engine-owned
  3MF project with a C-ABI `NSA1SceneObject` payload (vertices, indices,
  column-major transform), plus (P3-003) the resolved `profileSelection`
  config. Metal buffers are built once per mesh and cached; only
  per-object uniforms are encoded each frame. Project replacement is
  transactional: a failed load retains the open scene.
- **Conventional slicing (P1-008)**: `nsa1_slice_to_gcode` (CSlic3rBridge)
  builds a `Slic3r::Model` from placed scene objects, seeds
  `DynamicPrintConfig::full_print_config()` via the shared
  `build_full_config` helper (also used by `nsa1_store_3mf`), overlays the
  resolved A1 profile fields (`BambuProfileLoader`/`SlicingJob`, including
  `include`-template and user-override merging as of P3-003), then calls
  `Print::apply`/`validate`/`process`/`export_gcode`. **Upstream bug
  worked around**: `full_print_config()`'s cloned `coEnum`/`coEnums`
  defaults have a null `keys_map` (only `create_default_option()` wires it
  up); null-derefs on `deserialize()`/`serialize()`. Fixed with a repair
  pass (`repair_enum_keys_map`, shared helper) copying
  `ConfigOptionDef::enum_keys_map` onto any option instance missing it,
  run immediately after seeding, before any overrides, and again
  (defensively) after reading a project's config back. Re-verified this
  session: reproduced the real SIGSEGV with the pass disabled, confirmed
  fixed, added `SlicingJobTests.testEnumProfileOptionsSurviveRepairedKeysMap`.
  Only other `full_print_config()` caller in the vendored tree
  (`Calib.cpp`) avoids the bug by a different pattern (`.apply()` over
  already-keyed config, never direct `deserialize()`) that doesn't fit our
  profile-overlay use case — see ARCHITECTURE.md P1-008 for the full
  writeup.
- **Per-nozzle custom G-code templates (P1-008 follow-up, this session)**:
  `BambuProfileLoader.resolve` now merges each profile's `include` list
  (per-nozzle `machine_start_gcode`/`machine_end_gcode`/etc. template
  fragments) using the same three-tier precedence as upstream
  `PresetBundle.cpp` (inherits chain → each include's own fields in list
  order → the profile's own fields win last). Closes P1-008's known gap:
  slicing now uses the real A1-specific G-code templates, not the
  engine's generic defaults.
- **G-code visualization (P1-009)**: `Print::export_gcode`'s
  `GCodeProcessorResult::moves` (real per-move toolpath data) is returned
  through `nsa1_slice_to_gcode`'s optional `NSA1Toolpath**` out-param as
  flat line segments. `MetalRenderer` draws this as a GPU line-list
  (extrude orange, travel gray) via a dedicated compiled pipeline.
  `ProjectDocument.slice()` runs the real pipeline via `Task.detached` off
  the `@MainActor`, wired to a toolbar "Slice" button. Now driven by
  `document.profileSelection` (P3-003) instead of a hardcoded default.
- **Advanced slicing settings (P3-003)**: `SlicingSettingsView` (sheet,
  opened via a toolbar "Settings…" button) exposes printer/nozzle,
  process, and filament pickers (filtered live to each machine's real
  `compatible_printers` list) plus layer height/wall loops/infill
  density/support/nozzle+bed temperature overrides. All backed by
  `SlicingJob.ProfileSelection` (now carries an `overrides: [String:
  String]` dict) and validated via `SlicingJob.validate` before every
  slice/save (not just UI-level filtering). Persistence required
  extending `nsa1_store_3mf` to accept config entries and adding
  `nsa1_load_3mf_config` — the latter reads the 3MF's
  `Metadata/Slic3r_PE.config` zip entry directly (via
  `miniz_extension.hpp`, the same helpers `3mf.cpp` itself uses) and
  parses it with `ConfigBase::load_from_gcode_string_legacy`, because
  **`Slic3r::load_3mf`'s own config out-param is dead code upstream** —
  the archive-entry read branch is inside a `/* ... */`-commented-out
  block in `3mf.cpp`'s importer (write path is live, read path isn't;
  BambuStudio's GUI apparently restores project settings through its
  separate, unvendored `src/slic3r/GUI` preset-bundle layer instead).
- Printer networking (A1 discovery/MQTT): reimplemented natively in Swift
  from reverse-engineered protocol docs — Bambu's own implementation is
  closed-source (`bambu_networking` plugin, no public source). Not
  hardware-verified against a real printer (see TODO.md P2-002/003/006).

## Uncommitted changes
None after the P3-002 Task 1 resource-milestone commit.

## Known blockers
P3-002 has two verified engineering gates, not reasons to reduce scope:
- Only pressure-advance has a public reusable `libslic3r` generator
  (`CalibPressureAdvancePattern`); upstream flow/temp/retraction/max-flow
  workflows are GUI orchestration around real resource models and config
  ranges. The plan isolates that adaptation in a narrow C++ bridge helper;
  never post-edit exported G-code as the primary implementation.
- A1 profile files establish printer/nozzle/filament compatibility but do
  not declare calibration-command firmware capabilities. Pressure advance
  must be capability-gated until actual firmware evidence is supplied;
  workflow generation is not silently omitted.
- THIRD_PARTY_LICENSES.md still has a few "📋 public record, not
  re-verified" rows (Boost, CGAL, OCCT, Assimp, OpenCV, TBB, NLopt,
  FreeType, GMP, MPFR, curl, OpenSSL, expat, libjpeg-turbo, libpng,
  zlib, CocoaMQTT) — verify against exact vendored LICENSE files before
  any distribution decision. CGAL's dual GPL/LGPL licensing specifically
  needs scoping to the exact CGAL packages `libslic3r_cgal` links.
- No hardware A1/AMS Lite available: all printer-facing code remains
  protocol/documentation-level verified only.
- P3-003's settings UI intentionally exposes 6 common overrides, not the
  full BambuStudio settings surface; `SlicingJob.overridableKeys` is the
  extension point.

## Next recommended action
- Continue P3-002 Task 2 (request/capability validation) after committing
  the verified calibration-resource milestone; implement flow-rate before
  pressure advance, temperature, retraction, then max volumetric speed.
- P2-004/P2-007/P2-008 need real hardware, not available this session; the
  upload protocol (P2-004, likely FTP-over-TLS per RESEARCH-P0-007.md)
  could still be implemented and tested against a local server, the same
  way P2-003's MQTT client was tested against a local broker.

## Relevant test/build commands
- `Scripts/build-libslic3r.sh` — one-time/idempotent engine build.
- `swift build` / `swift test` / `swift run NativeSlicerA1`.
- `swift test --filter ProjectDocumentTests` — real 3MF geometry/transform
  and profile-selection round-trip, plus failed-load preservation.
- `swift test --filter MetalRendererTests` — real mesh upload/draw and
  real toolpath upload/draw through the compiled GPU pipelines.
- `swift test --filter SlicingJobTests` — real end-to-end G-code
  generation through the A1 profile closure, keys_map regression tests,
  include-template resolution, P3-003 validation/override tests.
- `swift test --filter BambuProfileLoaderTests` — inherits/include
  resolution, instantiable-profile filtering, compatibility checks.
