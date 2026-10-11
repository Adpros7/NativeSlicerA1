# Feature Parity Audit (P3-001)

Audited against actual upstream source, not documentation/changelogs:

- **BambuStudio**: `.research/BambuStudio`, tag `v02.08.04.61` (`f5e51a2`) — same pin as `vendor/BambuStudio` (the engine this project actually builds).
- **OrcaSlicer**: `.research/OrcaSlicer`, tag `v2.4.2` (`8500fcd`).
- **NativeSlicerA1**: this repo's `Sources/NativeSlicerA1/*.swift` + `Sources/CSlic3rBridge/`.

Methodology: 6 parallel research passes, each grepping the real upstream trees for the implementing code and reading the actual hit (not recalled from memory/docs), cross-referenced against our own Swift/C++ source. Status: **full** / **partial** / **none**. Priority: **P0** (safety/correctness-blocking, generally already done) / **P1** (high user value) / **P2** (medium) / **P3** (low) / **P4** (large subsystem, low near-term value for an A1-only single-material/single-plate product). Full per-feature detail (every row, every citation) is in the companion research docs this file summarizes: `RESEARCH-P0-011.md` (original 25-category draft, superseded by this pass for citation rigor) and `RESEARCH-P0-011-CONNECTIVITY.md` (printer connectivity/monitoring/MakerWorld detail).

This supersedes `TODO.md` P0-011's "draft, needs citations" status — treat this file as the current, cited feature-parity record; **P0-011 is now done**.

## 1. Model import/export

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| STL import | full — `src/libslic3r/Format/STL.cpp` | full (shared) | **full** — `SlicingEngineBridge.swift:120-125` | — | none |
| STL export | full — `Format/STL.cpp:35-120` (`TriangleMesh::write`) | full (shared) | **none** | P1 | no `nsa1_store_stl` bridge function |
| OBJ import | full — `Format/OBJ.cpp` (`objparser`+`ObjColorUtils`) | full (shared) | **none** | P1 | no `nsa1_load_obj_mesh` bridge |
| OBJ export | full — `Format/OBJ.cpp:50-200` | full (shared) | **none** | P2 | no `nsa1_store_obj` bridge |
| 3MF import (multi-object + matrices) | full — `Format/3mf.cpp:800-850,1768-1815` | full (shared) | **full** — `nsa1_3mf_object_count`/`nsa1_load_3mf_mesh`/`nsa1_3mf_object_matrix` | — | none |
| 3MF export (matrices + config) | full — `3mf.cpp:2140-2280,2880+` | full (shared) | **full** — `nsa1_store_3mf` + `ProjectDocument.save` | — | none |
| STEP import | full — `Format/STEP.cpp` (OpenCascade tessellation) | full (shared) | **none** | P1 | OpenCascade already linked into `libslic3r.a`; needs `nsa1_load_step_mesh` wrapper only |
| Unit detection (inch-scale warning) | partial — passive `unit=` scaling only, `3mf.cpp:1556`, no dialog | partial (same) | **none** | P2 | no UI; 3MF `unit` attribute parsed but not surfaced |

## 2. Geometry transformations

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| Translate | full — `Model.hpp:476` | full (shared) | **full** — `Transform.translated(by:)` | — | none |
| Rotate (free axis) | full — `Model.hpp:487` | full (shared) | **partial** — `Transform.rotated(by:)` takes a raw quaternion | P1 | no angle+axis convenience constructor for UI |
| Rotate (90° increments) | full | full (shared) | **partial** | P1 | no axis-aligned rotation buttons in UI |
| Scale (uniform/non-uniform) | full — `Model.hpp:480` | full (shared) | **partial** — `Transform.scaled(by:)` works, no "lock uniform" UI toggle | P1 | UI gap only, engine path complete |
| Mirror/flip | full — `Model.hpp:489` (normal-flip on negative scale) | full (shared) | **partial** — TRS decomposition mathematically supports reflection, no explicit `mirror(axis:)` method or UI | P1 | add `Transform.mirror(axis:)` + buttons |
| Auto-orient | full — `Orient.hpp:158-163` | full (shared) | **none** | P2 | no `nsa1_auto_orient` bridge |
| Auto-arrange | full — `Arrange.hpp:208-221` (libnest2d) | full (shared) | **none** | P2 | no `nsa1_auto_arrange` bridge |
| Non-destructive undo/redo | full | full (shared) | **full** — `UndoStack<Transform>`, mesh geometry never mutated | — | none |

## 3. Project persistence & compatibility

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| Instance matrices (4×4 TRS) | full | full (shared) | **full** — `nsa1_3mf_object_matrix`, float32 (±0.001mm sufficient) | — | none |
| Per-instance printable flag | full — `3mf.cpp:1813,1903,2865` | full (shared) | **partial** — engine respects it internally, no UI toggle | P2 | add visibility checkbox |
| Per-object settings (vs. global-only) | partial — volume-level, not object-level, even upstream | partial (same) | **partial** — only one global `ProfileSelection` per scene | P2 | out of scope beyond upstream's own limits |
| Cross-slicer 3MF round-trip | full (standard 3MF) | full (shared) | **full** — uses the identical vendored `3mf.cpp`, no NSA1-specific format | — | none |
| Multi-plate assignment + per-plate G-code | full — `bbs_3mf.cpp`, `PartPlate.hpp:79-650` | full (shared, no multi-plate UI in Orca) | **none** | P3 | A1 is single-plate hardware; low value until multi-job queuing matters |

## 4. Object splitting & connectors

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| Cut tool (plane) | full — `GUI/Gizmos/GLGizmoCut.cpp` | full (shared) | **none** | P1 | no cut gizmo, no `Cut` bridge |
| Connector types (Plug/Dowel/Snap/Thread) | full — `Model.hpp:249-255`, mesh generators (`its_make_snap` etc.) | full (shared) | **none** | P1 | needs `CutConnectorType` enum + mesh-gen bridge |
| Connector gizmo (add/edit/delete) | full — `GLGizmoAdvancedCut.cpp` | partial | **none** | P2 | depends on cut tool first |
| Reversible splitting (undo) | partial — `CutUtils.hpp:78-120`, even upstream | partial | **partial** — generic `UndoStack` exists, no cut-specific `cut_id` integration | P2 | depends on cut tool first |

## 5. Automatic orientation & arrangement

Covered in §2 (auto-orient, auto-arrange) plus:

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| Multi-plate build layout | full — `PartPlate.hpp` | full (shared) | **none** | P1 | see §3 multi-plate note — deferred, A1 single-plate |

## 6. Supports & modifiers

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| Tree support generation | full — `Support/TreeSupport.hpp:365-388` | full (shared) | **partial** — `enable_support` reaches the real `Print::process()` pipeline through `SlicingSettingsView`/`SlicingJob`; profile-selected support defaults also reach it | P1 | no support-type picker (tree vs. linear), blocker/enforcer zones, or support-specific preview |
| Support blocker/enforcer zones | full — `Model.hpp:331-338` | full (shared) | **none** | P1 | needs `ModelVolumeType` + painting gizmo |
| Modifier mesh (local config override) | full — `Model.hpp:331-338` | full (shared) | **none** | P2 | needs `PARAMETER_MODIFIER` + painting + spatial lookup in slicing |
| Variable layer height | full — `Slicing.hpp:133-134` | full (shared) | **none** | P2 | needs `layer_config_ranges` + Z-range UI |
| Seam painting (dedicated gizmo) | full — `GLGizmoSeam.hpp` | full (shared) | **none**; seam *position* config exists (see §9) but no paint tool | P3 | low value vs. the 4-mode seam picker already planned |

## 7. Multi-plate workflows

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| Per-plate settings | full — `GUI/PartPlate.cpp:5364-5655` | full (shared) | **none** | P2 | deferred with multi-plate (§3/§5) |
| Multi-plate G-code export | full — `GCode.cpp:2553,3280,5101` | full (shared) | **none** | P1* | *high value only once multi-plate exists at all; deferred |
| Locked plate (arrange constraint) | full — `Arrange.hpp:56` | partial | **none** | P3 | deferred |
| Plate preview/selection UI | full — `GUI/Plater.cpp` | full (shared) | **none** | P2 | deferred |

**Multi-plate verdict**: real upstream value (batch jobs, per-plate settings), but the A1 is single-plate hardware and every multi-plate feature above depends on first building plate infrastructure nothing else needs — correctly low near-term priority relative to single-object features above.

## 8. Printer, filament, process settings

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| Settings *engine* availability (~600 options) | full — `PrintConfig.cpp`, 596 options | full — 781 options (broader non-FFF scope) | **full** — `BambuProfileLoader` loads the entire vendored A1 profile closure; all values already reach `Print::process()` | — | none at the engine layer |
| Settings *UI* surface | full (hundreds of controls) | full (hundreds of controls) | **partial** — `SlicingSettingsView` exposes 6 overrides (layer height, walls, infill, supports on/off, nozzle/bed temp) — **intentional P3-003 scope**, not an oversight | P1 | expand `SlicingJob.overridableKeys` as specific settings prove worth exposing (next candidates below) |
| Support type picker (tree vs. linear) | full | full | **none** (on/off toggle only) | P1 | add to `overridableKeys` |
| Seam position picker | full — `GCode/SeamPlacer.cpp:1402-1503` (aligned/nearest/back/rampart) | full (shared) | **none** (config loads, no UI) | P2 | add to `overridableKeys` |
| Ironing | full — `PrintConfig.cpp:4230-4240` | full (shared) | **partial** — profile-selected ironing config already reaches the real engine, no direct UI override | P3 | add UI only after a demonstrated A1 workflow need |
| Arachne variable-width walls | full — `PerimeterGenerator.cpp:1464-1800` | full (shared) | **partial** — the vendored engine contains it and profile values reach `Print::process()`, but the UI cannot select/inspect `wall_generator` | P3 | UI/preview gap; do not reimplement the upstream engine |
| XY contour compensation | full — BambuStudio-specific | none (not in OrcaSlicer) | **partial** — profile config is passed through, no direct UI override | P3 | low-value dimensional-accuracy UI control |

## 9. Multicolor printing & AMS Lite

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| AMS Lite slot-state + MQTT mapping | partial (generic AMS, no Lite-specific path) | none | **full** — `AMSLite.swift`, arguably **ahead** of both upstreams for this specific product | — | none |
| Multicolor segmentation (MMU Voronoi) | full — `MultiMaterialSegmentation.cpp` (~2600 lines) | full (shared) | **none** | P4 | large subsystem; A1 has no AMS-driven per-face painting workflow planned |
| Painting tools (brush/fill/triangle/sphere) | full — `GLGizmoMmuSegmentation.cpp` | full (shared) | **none** | P4 | depends on segmentation engine above |
| Tool-change sequencing + wipe tower G-code | full — `GCode.cpp` tool-change integration | full (shared) | **none** | P4 | AMS Lite swaps filament without a wipe tower on this product class; lower relative value |
| Color-decomposition recipe (CMYK blend) | full — `ColorDecomposeRecipe.cpp` (Bambu-exclusive) | **none** | **none** | P4 | Bambu-exclusive, no OrcaSlicer precedent, low near-term value |

## 10. Purge optimization & prime towers

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| Wipe tower sizing/placement | full — `GCode/WipeTower.cpp:1752-1760`, `Print.cpp:1010-1013` | full (shared) | **none** | P4 | entire subsystem absent; see §9 — AMS Lite swap behavior differs from X1C's multi-nozzle wipe-tower model |
| Purge volume calibration matrix | full — `Print.cpp:3971-3984` | full (shared, `WipeTower.cpp:1562`) | **none** | P4 | depends on wipe tower existing |
| Purge G-code emission | full — `GCode.cpp:944-1062` | full (shared) | **none** | P4 | depends on wipe tower existing |

## 11. Sequential & by-object printing

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| `print_sequence` config (ByLayer/ByObject) | full — `PrintConfig.hpp` enum | full (shared) | **none** | P3 | A1 is single-material; by-object mainly helps multi-part batch jobs |
| Sequential collision detection | full — `Print.cpp:602-946` (`sequential_print_clearance_valid`) | full (shared) | **none** | P4 | safety-relevant *if* by-object printing is ever enabled — must ship together with the config option, never the option alone |
| `ByObjectPrintData` + ordering | full — `ByObjectPrintData.hpp/.cpp` | none (different architecture) | **none** | P4 | depends on the above |
| Per-object G-code generation | full — `GCode.cpp:3227-3232,1918,2328` | full (`GCode.cpp:2730-3344`, different structure) | **none** | P4 | depends on the above |

## 12. G-code generation & visualization

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|---|
| G-code generation (`Print::process`/`export_gcode`) | full | full (shared) | **full** — `SlicingJob.swift:137-145` via the same pipeline | — | none |
| Toolpath visualization (per-move) | full — multi-mode (FeatureType/Height/Feedrate/Temperature/LayerTime/...) | full (shared) | **partial** — extrude(orange)/travel(gray) only, no mode switching | P2 | add a view-mode selector over `GCodeProcessorResult` fields already available |
| Print time estimation | full — `GCodeProcessor.cpp:2905+` (`TimeMachine`) | full (shared) | **none** | P1 | `nsa1_slice_to_gcode` already runs `GCodeProcessorResult` through the engine — `PrintEstimatedStatistics` is sitting there unused |
| Filament usage (length/mass per extruder) | full — `GCodeProcessor.cpp:3407-3424` | full (shared) | **none** | P1 | same `GCodeProcessorResult`, different field |
| Layer-by-layer scrubbing with time labels | full | full (shared) | **none** | P2 | depends on print-time estimation above |

## 13. Calibration tools (feeds directly into P3-002)

All five use shared `libslic3r` infrastructure in `src/libslic3r/Calib.cpp`/`Calib.hpp` plus GUI orchestration in `src/slic3r/Utils/CalibUtils.cpp`, identical between BambuStudio and OrcaSlicer (OrcaSlicer is a near-verbatim fork of this file, confirmed by reading both).

| Feature | BambuStudio citation | NativeSlicerA1 | Priority | A1 applicability |
|---|---|---|---|---|
| Flow-rate (2-pass coarse/fine) | `CalibUtils.cpp:745-945`; models `resources/calib/filament_flow/flowrate-test-pass{1,2}.3mf` | **none** | P2 | required first; directly useful per-filament tuning |
| Pressure-advance pattern | `Calib.cpp:498+` (`CalibPressureAdvancePattern`) | **none** | P2 | required second; gate generation on confirmed active-printer/firmware support rather than assuming an A1 capability either way |
| Temperature tower | `CalibUtils.cpp:1348-1391` (`calib_temptue`); model `resources/calib/temperature_tower/temperature_tower.stl` | **none** | P2 | required third |
| Retraction | `CalibUtils.cpp:1613-1705` (`calib_retraction`); model `resources/calib/retraction/retraction_tower.stl` | **none** | P2 | required fourth |
| Max volumetric speed | `CalibUtils.cpp:1428-1530` (`calib_max_vol_speed`) | **none** | P2 | required fifth; validate the active A1/nozzle/filament combination before generating G-code |
| Calibration result polling/caching (device-side) | `CalibUtils.cpp:630-780` + `DeviceManager.cpp` (MQTT) | **none** | P3 | useful after workflows ship, but manual result entry/application must work first |

Shared pattern for all of these: load a bundled calibration model (3MF/STL), apply per-layer or per-object `DynamicPrintConfig` overrides during `Print::process()` (same mechanism `SlicingJob.overrides` already uses for P3-003's 6 settings — a proven extension point; expose only the additional C-ABI state needed by a chosen upstream calibration API), slice through the existing real pipeline, then allow manual result selection/application. Printer result polling over MQTT is optional enhancement, not a prerequisite.

## 14. Printer discovery & connectivity

(Full detail: `RESEARCH-P0-011-CONNECTIVITY.md`.)

| Feature | BambuStudio/OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|
| SSDP discovery | closed-source (`bambu_networking` plugin) — RESEARCH-P0-007.md | **full**, no plugin dependency | — | NativeSlicerA1 is cleaner here than either upstream |
| MQTT/TLS connection | closed-source plugin | **full** — core report/request; pause/resume/stop convenience methods missing | P2 | add convenience commands |
| Print upload (FTPS, port 990) | closed-source plugin | **none** | P1 | reliable only for <250KB files per A1 hardware limits (RESEARCH-P0-007.md) |

## 15. Monitoring & camera features

| Feature | BambuStudio/OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|
| Print status monitoring UI | closed-source plugin | **none** (transport ready, no UI) | P1 | MQTT report parsing exists for AMS; needs general status JSON parsing + UI |
| Camera streaming | closed-source plugin, proprietary port-6000 protocol | **none** | P2 | reverse-engineered-only per RESEARCH-P0-010.md; 1fps limitation makes this a low-fidelity feature regardless |
| Local failure detection | closed-source plugin | **none** | P3 | depends on monitoring UI first |

## 16. MakerWorld integration

| Feature | BambuStudio/OrcaSlicer | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|
| Browsing/downloading/auth | proprietary bind-ticket auth mechanism, closed-source — RESEARCH-P0-009.md | **none** | P2 | **licensing risk identified**: recommend delegating to the system browser for auth rather than reimplementing Bambu's proprietary bind-ticket flow |

## 17. Error handling & recovery

| Feature | Upstream pattern | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|
| Slicing failure severity (critical vs. recoverable) | full — `Plater.cpp:13141-13160` (`WarningLevel::CRITICAL`/`NON_CRITICAL`, modal vs. notification) | **partial** — `ProjectDocument.lastError` is one undifferentiated string, cleared on next op | P1 | add severity tag to `SlicingEngineError`, dual-path presentation |
| Profile compatibility validation | full — `Print.cpp:90-130` | **full** — `SlicingJob.validate` (P3-003) already matches this pattern | — | none |
| Corrupt/malformed file handling | partial even upstream (exception → modal, no repair) | **partial** — caught, but silently cleared, no file-path/reason detail | P1 | surface as a blocking alert with reason; partial-3MF recovery (import readable objects, skip broken ones) |
| Printer communication failure recovery | full — `DeviceManager.cpp` reconnect/offline-state logic | **none** | P2 | no reconnect/backoff/offline-state in `PrinterConnection.swift` |

## 18. Performance

| Feature | Upstream | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|---|
| Slicing engine speed | no published benchmarks either upstream | **none** — no instrumentation | P2 | add timing + a 3-model benchmark baseline (feeds Phase 6 anyway) |
| Viewport rendering | wxWidgets/OpenGL, no native Metal | **full** architecture (GPU mesh caching, cached-per-mesh buffers) — no FPS/memory instrumentation | P2 | add FPS counter + GPU memory profiling |
| Large-model/memory handling | no explicit OOM handling either upstream | **partial** — loads entire mesh into RAM, no size warning or OOM handling | P2 | add a triangle-count/file-size warning threshold |

## 19. Accessibility

NativeSlicerA1's SwiftUI choice is **structurally ahead** of both upstreams here (wxWidgets has essentially no native macOS accessibility integration) — this section is about NativeSlicerA1's own gaps, not parity with upstream.

| Feature | NativeSlicerA1 | Priority | Gap |
|---|---|---|---|
| Settings form keyboard navigation | **full** (SwiftUI `Form` controls are keyboard-navigable by default) | — | none |
| Dynamic Type | **full** (system text styles auto-scale) | — | verify at XXXL sizes, not yet done |
| VoiceOver (standard controls) | **partial** (buttons/lists accessible by default; `ObjectListView` label format not verified) | P1 | audit + test with VoiceOver enabled |
| **Metal viewport accessibility** | **none** — no `.accessibilityLabel`, no synthetic per-object children, drag/scroll gestures have no keyboard equivalent | P1 | this is the one real structural gap; everything else is ahead by construction |
| Color contrast / colorblind-safe | **partial** (semantic SwiftUI colors, not explicitly audited) | P2 | run macOS Accessibility Inspector's Color Blindness Simulator |

## Summary: priority rollup

| Priority | Count (approx., this audit) | Representative items |
|---|---|---|
| P1 | ~17 | STL/OBJ/STEP import-export, rotate/scale/mirror UI, cut tool, connector types, support generation, print-time/filament estimation, print upload, status monitoring, error severity, Metal viewport accessibility |
| P2 | ~26 | Auto-orient/arrange, seam/ironing UI, **all five requested calibration workflows**, G-code view modes, camera streaming, MakerWorld, performance benchmarking, printer reconnect logic |
| P3 | ~11 | Multi-plate, Arachne walls, sequential printing config, locked plates |
| P4 | ~12 | Multicolor/MMU segmentation, wipe tower/purge, by-object collision+ordering — large subsystems, low near-term value for this single-material/single-plate product |

Next: TODO.md Phase 1/3/4 entries updated with these findings; P3-002 (calibration) implementation proceeds directly from §13 above.
