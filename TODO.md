# Development Tasks

## Phase 0: Research and Architecture

- [x] P0-001: Audit latest stable Bambu Studio source code. See RESEARCH.md.
- [x] P0-002: Audit latest stable OrcaSlicer source code. See RESEARCH.md.
- [x] P0-003: Identify reusable slicing components. See RESEARCH.md.
- [x] P0-004: Verify licenses and redistribution obligations. AGPLv3 constraint documented in RESEARCH.md; this repo licensed AGPLv3 (LICENSE).
- [x] P0-005: Investigate Swift/C++ interoperability. See ARCHITECTURE.md.
- [x] P0-006: Investigate Metal rendering architecture. See ARCHITECTURE.md.
- [x] P0-007: Investigate Bambu A1 communication protocols. See RESEARCH-P0-007.md.
- [x] P0-008: Investigate AMS Lite integration. See RESEARCH-P0-008.md.
- [x] P0-009: Investigate MakerWorld integration. See RESEARCH-P0-009.md.
- [x] P0-010: Investigate A1 camera capabilities. See RESEARCH-P0-010.md.
- [x] P0-011: Generate feature-parity matrix. See RESEARCH-P0-011.md.
- [x] P0-012: Finalize application architecture. See ARCHITECTURE.md.
- [x] P0-013: Establish build and testing infrastructure. SwiftPM package (`swift build`/`swift test`), verified app launches.

## Phase 1: Application Foundation

- [x] P1-001: Create native macOS application. SwiftUI skeleton app, builds and launches (`Sources/NativeSlicerA1`).
- [ ] P1-002: Implement Metal viewport.
- [ ] P1-003: Integrate established slicing engine.
- [ ] P1-004: Implement STL importing.
- [ ] P1-005: Implement 3MF importing.
- [ ] P1-006: Implement object transformations.
- [ ] P1-007: Implement project persistence.
- [ ] P1-008: Implement conventional slicing.
- [ ] P1-009: Implement G-code visualization.

## Phase 2: Printer Integration

- [ ] P2-001: Import A1 printer profiles.
- [ ] P2-002: Implement printer discovery.
- [ ] P2-003: Implement LAN communication.
- [ ] P2-004: Implement print upload.
- [ ] P2-005: Implement device monitoring.
- [ ] P2-006: Implement AMS Lite mapping.
- [ ] P2-007: Validate printer-specific G-code.
- [ ] P2-008: Perform physical A1 validation.

## Phase 3: Feature Parity

- [ ] P3-001: Implement audited missing features.
- [ ] P3-002: Implement calibration workflows.
- [ ] P3-003: Implement advanced slicing settings.
- [ ] P3-004: Implement multicolor painting.
- [ ] P3-005: Implement support painting.
- [ ] P3-006: Implement project compatibility.
- [ ] P3-007: Validate feature-parity matrix.

## Phase 4: Geometry

- [ ] P4-001: Implement unit detection.
- [ ] P4-002: Implement manual mesh repair.
- [ ] P4-003: Implement non-destructive transformations.
- [ ] P4-004: Implement automatic model splitting.
- [ ] P4-005: Implement connector presets.
- [ ] P4-006: Implement connector customization.
- [ ] P4-007: Implement connector reversibility.
- [ ] P4-008: Implement multi-plate arrangement.
- [ ] P4-009: Implement assembly previews.

## Phase 5: Online Models

- [ ] P5-001: Implement authorized authentication.
- [ ] P5-002: Implement MakerWorld browsing.
- [ ] P5-003: Implement model downloading.
- [ ] P5-004: Implement direct slicing workflow.
- [ ] P5-005: Implement additional repository integrations.

## Phase 6: Optimization

- [ ] P6-001: Establish conventional slicing benchmarks.
- [ ] P6-002: Implement color-transition analysis.
- [ ] P6-003: Implement purge optimization.
- [ ] P6-004: Implement region scheduling.
- [ ] P6-005: Implement collision validation.
- [ ] P6-006: Implement optimization reports.
- [ ] P6-007: Benchmark against OrcaSlicer.
- [ ] P6-008: Validate optimized prints on hardware.

## Phase 7: Intelligent Features

- [ ] P7-001: Implement camera access.
- [ ] P7-002: Implement local failure detection.
- [ ] P7-003: Implement monitoring notifications.
- [ ] P7-004: Implement optional automatic intervention.
- [ ] P7-005: Implement orientation optimization.
- [ ] P7-006: Implement slicing recommendations.
- [ ] P7-007: Implement G-code-to-3MF reconstruction.

## Phase 8: Production

- [ ] P8-001: Complete regression testing.
- [ ] P8-002: Complete security review.
- [ ] P8-003: Complete performance benchmarks.
- [ ] P8-004: Complete hardware validation.
- [ ] P8-005: Complete compatibility documentation.
- [ ] P8-006: Package macOS application.
- [ ] P8-007: Sign and notarize release.
- [ ] P8-008: Publish validated release.

## Task Completion Rules

Each task must eventually include:

- Acceptance criteria.
- Dependencies.
- Implementation references.
- Test references.
- Verification status.
- Associated Git commit.

Do not mark tasks complete until verified.

Expand this tracker after completing the initial source-code audit.