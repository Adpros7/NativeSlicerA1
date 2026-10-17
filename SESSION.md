# Session State

## Current phase
Phase 1 and Phase 4 (except conditional P4-002 repair) are complete.
Phase 5 is **not complete**: MakerWorld has only an intentionally safe
trusted-browser handoff; a real MyMiniFactory integration now exists
alongside it, itself not live-verified (Cloudflare + packaging blockers).
Phase 6 is **complete for everything verifiable without hardware/
OrcaSlicer** (P6-001–006 done; P6-007/P6-008 explicitly blocked, see
`BENCHMARKS.md`). A new user-requested **Phase 6.5 (Native Slicer
Usability)** was inserted into `TODO.md` immediately after Phase 6 and
is not started: the app currently launches to a blank viewport with no
plate/grid shown until import, and the toolbar already overflows at
default window width (confirmed live — the Optimization Report/
MakerWorld/MyMiniFactory/paint/cut-plane controls fall behind a `»`
chevron). Printer connectivity gaps (FTPS upload, structured MQTT
parsing, print controls) and Phase 7 remain pending.

## Last completed task
Phase 6 optimization milestone (commits `a814e63`..`213a174`..`dbc5002`..
`443b06c`..next), executed via `docs/superpowers/plans/
2026-10-16-phase6-optimization.md` (ledger: `.superpowers/sdd/
2026-10-16-phase6-optimization/progress.md`):

- **P6-001:** real A1-profile cube-slice benchmark harness in
  `BENCHMARKS.md`, run before/after every subsequent change. While
  wiring up the benchmark's metadata test, found and fixed a real bug:
  `nsa1_slice_to_gcode_with_statistics` built its `segments` vector but
  never allocated/assigned `*out_toolpath` and had no `return 0` on its
  success path at all — it fell off the end of a non-`void` function
  (undefined behavior in C++), so callers never reliably got a toolpath
  back from this one of the three slice entry points. `extruder_id`/
  `extrusion_role` were already populated correctly on the other two
  entry points (`nsa1_slice_to_gcode`, `nsa1_slice_to_gcode_with_
  modifiers`); this one needed both the missing fields and the missing
  toolpath/return-value wiring.
- **P6-002:** `Optimization.swift`'s `OptimizationReport.analyze
  (toolpath:)` reads the real `extruder_id`/`role` fields fixed above to
  report tool transitions and per-layer tool schedules — zero false
  transitions from travel moves, zero invented transitions for the A1's
  default single-tool output.
- **P6-003:** exposed real upstream `PrintEstimatedStatistics::
  flush_per_filament` (`GCodeProcessor.hpp:101`) through a new
  `flush_volumes_mm3` field on `NSA1EstimatedStatistics` →
  `EstimatedPrintStatistics.flushVolumesMM3` → `OptimizationReport.
  purgeVolumeMM3(_:)`. No automatic `flush_multiplier` changes.
- **P6-004:** `OptimizationReport.layerSchedules` reports the real
  engine's final per-layer tool order (same source data as P6-002, no
  new engine call) — observes upstream's actual schedule.
- **P6-005:** new sibling C ABI `nsa1_validate_collision`/
  `nsa1_free_collision_validation` builds/applies a real `Print` and
  calls its own `validate()` standalone (no G-code export) — the same
  `STRING_EXCEPT_OBJECT_COLLISION_IN_SEQ_PRINT` check `sliceToGCode`
  already runs, now callable on demand. Real overlapping-cube/
  spaced-cube tests both pass for the distinguishing reason (type 3 +
  message vs. valid + nil message).
- **P6-006:** `OptimizationReportView.swift` + `ProjectDocument.
  optimizationReport`/`refreshOptimizationDetails()`: tool-transition/
  layer data populate free from every slice's own toolpath (no extra
  engine cost); purge volume + collision status run two additional real
  engine calls only on explicit user action, never automatically on
  every ordinary slice.
- **P6-007:** attempted, blocked — no OrcaSlicer `.app`/CLI exists or is
  vendored in this environment; building it from source for one
  benchmark is a separate multi-hour undertaking, documented in
  `BENCHMARKS.md` rather than skipped silently.
- **P6-008:** blocked — no physical A1/AMS Lite hardware available;
  documented per AGENTS.md's hardware-verification rule.
- 8 new regression tests (`OptimizationTests`, `CollisionValidationTests`,
  `SlicingJobTests.testRealSliceCarriesEngineMoveMetadata`); full suite
  144→152 tests, 0 failures, run 3–5× after every C-ABI-touching commit
  per the toolchain-sensitivity rule below. Benchmarks recorded after
  each milestone in `BENCHMARKS.md`; no regression found (all within
  Debug-process noise, ~1.13–1.24s warm median throughout).

The user then added a **priority instruction mid-session**: insert a
dedicated UI/UX usability milestone immediately after Phase 6, before
declaring the app ready for users. `TODO.md`'s new "Phase 6.5" and
`docs/superpowers/specs/2026-10-16-native-slicer-ui-ux-design.md`
capture the requirements (always-visible A1 plate/grid/axes, populated
sidebar, Prepare/Preview/Device workflows, every control real and
reachable, multi-size visual verification). Not yet implemented.

## IMPORTANT finding (still applies): a real, reproduced, bisected toolchain/binary-layout sensitivity
While implementing P4-008's plate-id 3MF persistence, merely adding an
unused parameter to `SlicingEngine.storeThreeMF`'s Swift signature made
an UNRELATED, already-passing test fail deterministically across the
full suite while staying 100% green in isolation. Rigorously bisected.
Root cause not fully understood. Fixed by keeping `storeThreeMF`'s
signature byte-identical and adding new functionality via a WHOLLY
SEPARATE function instead — this pattern was followed again for P4-013's
`sliceToGCodeWithModifiers`. **Any future change to an existing hot-path
C-ABI function's signature should re-run the full suite 3-5× before
trusting a clean result; prefer adding a new sibling function instead.**
Confirmed again in this session: every P6-001/003/005 commit added a new
sibling C-ABI function or new fields on an existing output struct, never
changed an existing function's parameter list — ran the full suite 3-5×
after each regardless.

## Important technical decisions
- **MakerWorld integration is browser-delegated, not embedded** — a
  deliberate, user-confirmed scope boundary (asked via the `ask` tool
  given TODO.md's own explicit licensing-risk flag), not a technical
  limitation worked around. Any future MakerWorld work must stay within
  this boundary (no embedded webview, no reverse-engineered API calls,
  every URL gated through `MakerWorldLinks.isTrusted`).
- **New C-ABI functionality goes in sibling functions, not new
  parameters on existing ones** (P4-008/P4-013 finding above).
  `build_model_from_objects` (C++-internal, non-`extern "C"`) is the one
  exception since it never crosses the Swift/C ABI boundary directly.
- **`ModelVolumeType::PARAMETER_MODIFIER` + per-volume `ModelConfig` is
  sufficient for real local overrides** — confirmed via source
  investigation before writing code, proven via a real extrusion
  comparison test.
- **Two different 3MF formats exist in the vendored engine**:
  `Format/3mf.cpp` (legacy, used throughout) vs. `Format/bbs_3mf.cpp`
  (BambuStudio's separate full project format, not used here).

## Uncommitted changes
Phase 6.5 (UI/UX usability) design doc committed; implementation not yet
started. Working tree otherwise clean — every Phase 6 task committed and
pushed individually (see commits above). Full suite currently passes
152/152.

## Known blockers
- **MakerWorld actual auth/browse/download:** public API does not exist;
  reverse-engineering bind-ticket endpoints remains out of scope.
- **MyMiniFactory live OAuth/download:** requires user-supplied registered
  OAuth credentials and P8-006's packaged/Launch-Services-registered app.
  This environment's Cloudflare challenge prevents live API proof.
- **P6-007 OrcaSlicer benchmark:** no OrcaSlicer binary installed/vendored
  here; building it from source is out of proportion to one benchmark.
- **P6-008 hardware validation:** no physical A1/AMS Lite is available.
- P3-004 multicolor painting remains deferred; P4-002 needs an observed
  non-manifold repair case.

## Next recommended action
1. Implement Phase 6.5 (`TODO.md` P6.5-001..005): always-visible A1
   plate/grid/axes in `MetalViewport`/`MetalRenderer`, a populated
   sidebar (printer/filament/process/objects with real empty states),
   Prepare/Preview/Device workflows, toolbar reorganized so Import/
   Arrange/Slice/Export/Print never fall into the overflow chevron
   (confirmed live at 1500pt width — screenshot evidence this session),
   then screenshot-verify compact/standard/wide × light/dark.
2. After Phase 6.5, implement the software-verifiable printer
   connectivity gaps: FTPS upload (port 990 implicit TLS, `STOR` to
   `/sdcard/bbl_plater/...`), structured MQTT status-report parsing
   (`gcode_state`/`mc_percent`/`layer_num`/etc. per
   `RESEARCH-P0-007.md`), and pause/resume/stop/start convenience
   methods on `PrinterConnection` — add a permanent regression test
   (currently none exist for `PrinterConnection` despite the TODO.md
   claim of manual mosquitto verification).
3. Then audit/implement the software-verifiable slice of Phase 7
   (orientation optimization already has a P4-010 base; slicing
   recommendations and G-code-to-3MF reconstruction are feasible
   without hardware; camera access and auto-intervention are not).

## Relevant commands
- `swift build` / `swift test` / `swift run NativeSlicerA1`
- `swift test --filter MakerWorldLinksTests` — 4 real domain-trust tests
- `swift test --filter ModifierVolumeTests` — 2 real modifier-mesh tests
- `swift test --filter PlatePreviewTests` — 3 real plate-preview tests
- `swift test --filter MultiPlateTests` — 5 real multi-plate tests
- `swift test --filter CutModelTests` — 7 real cut/connector-boolean tests
- `swift test --filter ProjectDocumentCutTests` — 10 real cut/connector/modifier/undo tests
- `swift test --filter CutGroupIDPersistenceTests` — 2 real cut_id/3MF tests
- `swift test --filter ConnectorTests` — 6 real connector-mesh tests
- `swift test --filter VariableLayerHeightTests` — 2 real layer-height-range tests
- `swift test --filter SupportPaintingTests` — 5 real paint engine tests
- `swift test --filter RaycastTests` — viewport hit testing + ray-plane
- `swift test --filter AutoArrangeTests` — 3 orient/arrange tests
- `cd vendor/BambuStudio/build/arm64 && ninja libslic3r libnest2d` — only
  for temporary upstream instrumentation; ALWAYS revert vendor sources
  afterward (`git -C vendor/BambuStudio checkout --`).
- When touching an existing hot-path C-ABI function's signature: run the
  FULL suite 3-5× before trusting a clean result, or add a sibling
  function instead — see the toolchain-sensitivity finding above.
- Manual GUI smoke test: launch via a real `.app` bundle (the raw
  `.build/out/Products/Debug/NativeSlicerA1` executable run directly is
  NOT Dock-registered and exits when its launching terminal session
  ends) — wrap it: `mkdir -p /tmp/NativeSlicerA1.app/Contents/MacOS`,
  write a minimal `Info.plist`, symlink the built executable in, then
  `open -n /tmp/NativeSlicerA1.app`.
