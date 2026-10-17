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

**Interpretation:** warm median improved 2.7% (1.166 s → 1.135 s). The repair restores the statistics-path toolpath allocation/return and metadata but does not add a second engine pass or an extra copy beyond the existing C ABI output; this small change is within noisy Debug-process timing. It is recorded as a non-regression, not a broad performance claim.
