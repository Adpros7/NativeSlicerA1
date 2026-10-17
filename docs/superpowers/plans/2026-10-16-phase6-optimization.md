# Phase 6 Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the vendored engine's real color-transition, purge, ordering, and collision data; preserve validated conventional slicing; benchmark every optimization change.

**Architecture:** Keep all slicing algorithms in vendored libslic3r. Populate already-declared `NSA1ToolpathSegment` fields from `GCodeProcessorResult`, add only a dedicated collision-validation C ABI, and calculate Swift reports from the engine's emitted toolpath and `PrintEstimatedStatistics`. This keeps the established synchronous C bridge boundary and avoids new high-allocation models.

**Tech Stack:** Swift 5.10/SwiftUI, C++17 `libslic3r`, SwiftPM/XCTest, existing `CSlic3rBridge` C ABI.

**Spec:** `TODO.md` P6-001–P6-008; `FEATURE_PARITY.md` §§9–11/18; upstream citations in `agent://VisitingNarwhal`.

## Global Constraints

- Preserve vendor source integrity; bridge existing `Print`, `ToolOrdering`, `GCodeProcessorResult`, and `Print::validate` behavior only.
- Do not alter existing C function signatures; new C ABI must be a sibling function.
- Run the complete test suite 3–5 times after any bridge layout change per `SESSION.md`.
- Benchmark the same real A1-profile reference slice before and after every change; record command, runs, median, and environment in `BENCHMARKS.md`.
- P6-008 requires physical A1/AMS Lite validation and remains blocked without hardware.

## Review Focus

- A one-extruder A1 job has zero transitions and zero purge volume; report it as such, never invent savings.
- A transition must only count between consecutive extruding moves; travel/retractions must not create false color changes. Test in Task 2.
- Purge volume must come from upstream `PrintEstimatedStatistics.flush_per_filament`, not a geometric Swift estimate. Test in Task 3.
- Collision validation must preserve the upstream error message/type for `print_sequence=by_object`; overlapping parts must fail while spaced parts pass. Test in Task 4.
- Existing conventional `sliceToGCode` behavior/toolpath must remain byte-compatible in fields not previously unset. Exercise its real cube path in every full suite.

---

### Task 1: Benchmark baseline and bridge missing move metadata

**Files:**
- Modify: `Sources/CSlic3rBridge/CSlic3rBridge.cpp` toolpath extraction in all three real slice paths.
- Modify: `BENCHMARKS.md`.
- Test: `Tests/NativeSlicerA1Tests/SlicingEngineBridgeTests.swift`.

**Interfaces:**
- Produces populated existing `NSA1ToolpathSegment.extruder_id` and `.extrusion_role`; Swift already consumes them as `ToolpathSegment.extruderID`/`.extrusionRole`.

- [ ] Capture five baseline runs of the existing real A1-profile cube slice; record individual wall times and median.
- [ ] Write a failing real-slice test asserting every toolpath segment has a non-negative extruder ID and at least one extruding segment has a nonzero extrusion role.
- [ ] Populate the existing C struct fields directly from `GCodeProcessorResult::MoveVertex::extruder_id` and `::role`; do not modify a C function signature.
- [ ] Run the focused test and then the full suite 3–5 times; append after numbers and median to `BENCHMARKS.md`.
- [ ] Commit the independently verified metadata+benchmark milestone.

### Task 2: Color-transition and layer schedule report

**Files:**
- Create: `Sources/NativeSlicerA1/Optimization.swift`.
- Test: `Tests/NativeSlicerA1Tests/OptimizationTests.swift`.

**Interfaces:**
- Consumes: `[ToolpathSegment]` populated by Task 1.
- Produces: `OptimizationReport.colorTransitions`, `layerSchedules`, and `totalToolChanges`.

- [ ] Write failing tests for same-tool continuity, travel suppression, a two-tool A→B transition, and deterministic ascending-Z layer schedules.
- [ ] Implement `OptimizationReport.analyze(toolpath:statistics:)` by reading final engine-emitted non-travel moves, grouping by Z layer, and retaining first-seen tool order per layer.
- [ ] Verify tests and report a default single-tool real slice with zero color transitions rather than a false optimization claim.
- [ ] Commit Task 2.

### Task 3: Upstream purge statistics and safe purge comparison

**Files:**
- Modify: `Sources/CSlic3rBridge/include/CSlic3rBridge.h`, `Sources/CSlic3rBridge/CSlic3rBridge.cpp`, `Sources/NativeSlicerA1/SlicingEngineBridge.swift`.
- Modify: `Sources/NativeSlicerA1/Optimization.swift`.
- Test: `Tests/NativeSlicerA1Tests/OptimizationTests.swift`, `Tests/NativeSlicerA1Tests/SlicingEngineBridgeTests.swift`.

**Interfaces:**
- Produces: `EstimatedPrintStatistics.flushVolumesMM3` copied from upstream `PrintEstimatedStatistics::flush_per_filament` (GCodeProcessor.hpp:101), and report totals.

- [ ] Write a failing test that a real single-tool slice has an empty/zero upstream flush volume and a pure report total equals the sum of supplied volumes.
- [ ] Extend the C result struct and its free function allocation/deallocation to copy `flush_per_filament` in index order; do not change a C call signature.
- [ ] Map it into `EstimatedPrintStatistics`; report the real current purge volume and a comparison only when two existing engine configurations were actually sliced. Never reduce `flush_multiplier` automatically.
- [ ] Run focused tests and full suite 3–5 times, benchmark, then commit Task 3.

### Task 4: Structured upstream collision validation

**Files:**
- Modify: `Sources/CSlic3rBridge/include/CSlic3rBridge.h`, `Sources/CSlic3rBridge/CSlic3rBridge.cpp`, `Sources/NativeSlicerA1/SlicingEngineBridge.swift`.
- Test: `Tests/NativeSlicerA1Tests/CollisionValidationTests.swift`.

**Interfaces:**
- Produces: `SlicingEngine.validateSequentialCollision(objects:configEntries:) throws -> CollisionValidation` via a new sibling `nsa1_validate_collision` C ABI.

- [ ] Write failing tests using real placed cube meshes and `print_sequence=by_object`: overlapping/clearance-violating placement reports an upstream collision; sufficiently spaced placement validates.
- [ ] Implement the sibling C ABI by constructing/applying the real `Print`, calling `validate()`, and returning validity, `StringExceptionType`, warning bit, and copied message; free all returned memory through a paired free function.
- [ ] Verify focused collisions + 3–5 full suite runs, benchmark, then commit Task 4.

### Task 5: Optimization report surface and comparative benchmark

**Files:**
- Create: `Sources/NativeSlicerA1/OptimizationReportView.swift`.
- Modify: `Sources/NativeSlicerA1/ProjectDocument.swift`, `Sources/NativeSlicerA1/ContentView.swift`, `BENCHMARKS.md`, `TODO.md`, `FEATURE_PARITY.md`, `SESSION.md`.
- Test: `Tests/NativeSlicerA1Tests/OptimizationTests.swift`.

**Interfaces:**
- Consumes: Task 2 report + Task 3 purge stats + Task 4 collision result.
- Produces: SwiftUI report after a real slice; read-only unless the user explicitly changes an existing profile override.

- [ ] Write a test proving report totals derive solely from supplied actual data and a valid collision state is rendered as valid (not hidden).
- [ ] Store the latest real report in `ProjectDocument` after slicing; add an “Optimization Report…” toolbar entry that displays tool transitions, per-layer schedule, upstream purge volume, and collision status.
- [ ] Attempt an OrcaSlicer benchmark using an installed/pinned command-line binary. If unavailable, record the exact absent prerequisite and why `libslic3r`-only numbers are not an Orca comparison; do not fabricate a comparison.
- [ ] Record after measurements, document P6-008 hardware block, run build/full suite and GUI smoke, update tracker/session/parity docs, commit and push.
