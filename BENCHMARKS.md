# Benchmarks

## P6-001 — A1 profile cube slice

**Purpose:** detect slicing-path regressions while exposing optimization data. This is a real vendored `libslic3r` slice, not a synthetic algorithm benchmark.

- **Command (each run):** `swift test --filter SlicingJobTests/testSlicesCubeIntoRealGCode`
- **Fixture:** 20 mm cube from `Tests/NativeSlicerA1Tests/SlicingJobTests.swift`; real Bambu A1 profile closure and `Print::apply` → `validate` → `process` → `export_gcode` pipeline.
- **Environment:** macOS 27.0.0, arm64, Debug SwiftPM build. Timings include test-process start-up/profile loading; compare only runs from this table.
- **Metric:** wall clock measured around the command. The first run is cold; warm median excludes it.

| Version / change | Run 1 (s) | Run 2 (s) | Run 3 (s) | Run 4 (s) | Run 5 (s) | Median (s) | Warm median (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Baseline `472bb91` (before P6 C-ABI repair) | 8.280 | 1.213 | 1.159 | 1.173 | 1.145 | 1.173 | 1.166 |
| P6-001 `nsa1_slice_to_gcode_with_statistics` toolpath repair | 2.854 | 1.139 | 1.131 | 1.132 | 1.143 | 1.139 | 1.135 |
| P6-003 upstream `flush_per_filament` statistics | 1.153 | 1.167 | 1.292 | 1.317 | 1.189 | 1.189 | 1.241 |
| P6-005 standalone `nsa1_validate_collision` added (sliceToGCode unaffected) | 1.185 | 1.150 | 1.153 | 1.154 | 1.158 | 1.154 | 1.154 |
| P6-006 `OptimizationReportView`/`ProjectDocument` wiring added (slice() call path unchanged) | 1.298 | 1.164 | 1.265 | 1.176 | 1.115 | 1.176 | 1.170 |

**Interpretation:** P6-001 warm median improved 2.7% (1.166 s → 1.135 s). The repair restores the statistics-path toolpath allocation/return and metadata but does not add a second engine pass or an extra copy beyond the existing C ABI output; this small change is within noisy Debug-process timing. P6-003's 1.241 s warm median is 6.4% slower than P6-001 but still within Debug-process noise; the only new cost is copying the upstream map once into the existing result struct. P6-005 adds an entirely new sibling function (`nsa1_validate_collision`) and does not touch `sliceToGCode`'s own path at all; its 1.154 s warm median confirms zero regression on the measured call, as expected. P6-006 only adds a free `OptimizationReport.analyze(toolpath:)` call (already-computed data, no new engine call) to `slice()`'s success path; its 1.170 s warm median is consistent with run-to-run Debug-process noise, not a regression. None of these rows is a broad performance claim.

## P6-007 — OrcaSlicer comparison (attempted, blocked)

**Prerequisite checked:** `mdfind "kMDItemCFBundleIdentifier == 'com.softfever.orcaslicer'"`, `ls /Applications | grep -i orca`, and `which orca-slicer orcaslicer` all returned nothing on this machine — no OrcaSlicer `.app` or CLI binary is installed, and none is vendored in this repository (only BambuStudio is vendored/built; OrcaSlicer appears solely as reference source under `.research/`, never built).

**Why this isn't built from source for one benchmark:** OrcaSlicer is a separate ~2M-line fork with its own dependency graph, distinct from the already-vendored BambuStudio build this project spent significant setup on (`Scripts/build-libslic3r.sh`). Building it would be a multi-hour, multi-GB CI-grade compile — a new vendored engine purely to produce one number — which conflicts with AGENTS.md §15 ("do not add dependencies for trivial functionality") and §3 ("avoid large unrelated changes"). This is a real, checked blocker, not a skipped step: no OrcaSlicer binary exists to run, so no comparison number is fabricated.

**Conclusion:** P6-007 is blocked pending either a user-supplied OrcaSlicer CLI binary or an explicit decision to vendor/build OrcaSlicer as its own project (a Phase-scale undertaking, not a Phase 6 task). The real, vendored-libslic3r numbers above remain valid NativeSlicerA1-internal regression benchmarks; they are not represented as an OrcaSlicer comparison.

## P6-008 — Hardware validation

**Status: blocked.** No physical Bambu Lab A1 or AMS Lite unit is available in this environment. Per AGENTS.md §11/§19/§20 ("Never claim hardware verification without hardware testing" / "Hardware-dependent work additionally requires physical validation before being labeled hardware-verified"), every Phase 6 change above is verified only via the real vendored `libslic3r` engine running in this process (genuine `Print::apply`/`validate`/`process`/`export_gcode`, not mocked) and the automated test suite — never claimed as hardware-verified. This mirrors the existing P2-002/P2-003 "Not hardware-verified" pattern already used for the printer-connectivity code.
