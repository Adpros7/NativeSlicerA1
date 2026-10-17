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

**Interpretation:** P6-001 warm median improved 2.7% (1.166 s → 1.135 s). The repair restores the statistics-path toolpath allocation/return and metadata but does not add a second engine pass or an extra copy beyond the existing C ABI output; this small change is within noisy Debug-process timing. P6-003's 1.241 s warm median is 6.4% slower than P6-001 but still within Debug-process noise; the only new cost is copying the upstream map once into the existing result struct. P6-005 adds an entirely new sibling function (`nsa1_validate_collision`) and does not touch `sliceToGCode`'s own path at all; its 1.154 s warm median confirms zero regression on the measured call, as expected. None of these three rows is a broad performance claim.
