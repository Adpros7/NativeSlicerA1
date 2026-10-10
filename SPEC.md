# PROJECT SPECIFICATION
# Ultimate Native macOS 3D Slicer

## 0. Mission

Develop a production-quality, open-source, native macOS 3D slicer primarily optimized for the Bambu Lab A1 and AMS Lite.

The application must combine:

- Complete applicable Bambu Studio feature parity.
- OrcaSlicer's advanced slicing and calibration functionality.
- A genuinely native SwiftUI interface.
- Metal-accelerated 3D visualization.
- Seamless Bambu Lab printer integration.
- Native MakerWorld model browsing.
- Intelligent multicolor optimization.
- Automatic oversized-model splitting.
- Fully customizable, non-destructive connectors.
- Advanced toolpath simulation.
- Camera-based print failure detection.
- Manual mesh repair.
- Intelligent multi-plate management.
- G-code-to-3MF reconstruction.
- Comprehensive safety validation.
- High performance on Apple Silicon.

The application must be a real, functioning slicer, not a demonstration, prototype, or simulated interface.

The project must be developed incrementally through independently verified milestones.

Never sacrifice reliability or printer safety for performance or feature count.

---

# 1. Fundamental Engineering Philosophy

## 1.1 Reuse Before Reimplementation

Do not rewrite functionality already implemented correctly by established open-source slicers.

Before implementing any substantial feature:

1. Search Bambu Studio's source code.
2. Search OrcaSlicer's source code.
3. Examine relevant upstream dependencies.
4. Determine whether existing code can be reused.
5. Evaluate its licensing and compatibility.
6. Prefer direct reuse, adaptation, or a thin wrapper.
7. Implement new functionality only when existing solutions are unsuitable.

Priority order:

1. Reuse existing tested code.
2. Extend existing implementations.
3. Integrate established libraries.
4. Write minimal custom implementations.
5. Develop new algorithms only when necessary.

Avoid unnecessary abstraction layers.

Do not recreate established geometry, slicing, or printer communication systems without a documented technical reason.

Preserve upstream attribution and comply with all applicable licenses.

## 1.2 Native Where Practical

Use:

- Swift 6.
- SwiftUI.
- AppKit where necessary.
- Metal.
- Core ML.
- Foundation.
- Swift Concurrency.
- Native macOS security facilities.

Use C++ for existing slicing engines and computational geometry systems where appropriate.

Do not rewrite mature C++ algorithms in Swift merely to increase the percentage of Swift code.

Avoid Electron and browser-based application shells.

Use the smallest practical dependency set.

## 1.3 Minimal Code

Prefer the smallest correct implementation.

Rules:

- Avoid unnecessary classes and wrappers.
- Avoid speculative abstractions.
- Avoid duplicate logic.
- Avoid premature generalization.
- Avoid unnecessary configuration.
- Avoid unnecessary dependencies.
- Avoid boilerplate.
- Avoid overly defensive code that obscures actual failures.
- Avoid custom utilities already provided by standard libraries.
- Avoid large files containing unrelated responsibilities.
- Prefer straightforward, readable implementations.

Code should be concise without sacrificing correctness, safety, performance, or maintainability.

Never optimize for fewer lines at the expense of reliability.

---

# 2. Mandatory Source-Code Audit

Before implementing the application, audit the latest stable releases of Bambu Studio and OrcaSlicer.

Record:

- Version.
- Release date.
- Commit hash.
- License.
- Architecture.
- Dependencies.
- Slicing engine.
- Geometry libraries.
- Printer communication systems.
- Authentication mechanisms.
- Model management features.
- Supported settings.
- Calibration features.
- Advanced functionality.

Identify reusable components.

Create an architecture showing which components will be:

- Reused unchanged.
- Adapted.
- Wrapped.
- Replaced.
- Newly implemented.

Do not begin large-scale development until the initial audit is complete.

---

# 3. Feature Parity

The application must target complete applicable feature parity with the latest stable Bambu Studio release.

Also incorporate relevant OrcaSlicer features.

Maintain FEATURE_PARITY.md.

Each feature must record:

- Feature identifier.
- Name.
- Category.
- Upstream implementation.
- Relevant source files.
- Current implementation.
- Completion status.
- Acceptance criteria.
- Automated tests.
- Hardware validation status.
- Known limitations.

Statuses:

- Complete.
- Partial.
- Missing.
- Blocked.
- Not applicable.

A feature is complete only after verification.

Audit all applicable functionality, including:

- Slicing settings.
- Model importing.
- Model exporting.
- Object transformations.
- Plate management.
- Multicolor painting.
- Support painting.
- Seam painting.
- Connector generation.
- Mesh editing.
- Calibration.
- Filament management.
- AMS Lite.
- Printer management.
- G-code visualization.
- Print history.
- Timelapse.
- Sequential printing.
- Project management.
- Device monitoring.
- MakerWorld integration.
- Preferences.
- Advanced settings.
- Keyboard shortcuts.

Audit individual settings, not merely feature categories.

Maintain versioned compatibility records.

Never claim complete parity while applicable functionality remains missing or unverified.

---

# 4. Native macOS Application

Build a polished native macOS application.

Requirements:

- SwiftUI interface.
- Metal-based 3D viewport.
- Native menu bar.
- Native keyboard shortcuts.
- Drag-and-drop importing.
- Finder integration.
- Native file dialogs.
- Dark and light modes.
- Undo and redo.
- Autosave.
- Crash recovery.
- Background slicing.
- Responsive rendering.
- Accessible controls.
- Native notifications.
- Configurable preferences.

Support Apple Silicon natively.

Use AppKit when SwiftUI lacks necessary functionality.

Do not unnecessarily recreate macOS system components.

Keep the interface responsive during expensive operations.

---

# 5. Bambu Lab A1 Integration

The application must provide a plug-and-play experience for the Bambu Lab A1 and AMS Lite.

## 5.1 First-Run Setup

On first launch:

1. Detect Bambu Studio installations.
2. Identify compatible existing printer profiles.
3. Identify compatible filament profiles.
4. Offer to import preferences.
5. Offer to import authentication sessions where technically and legally supported.
6. Request explicit permission before accessing sensitive authentication data.
7. Validate imported credentials.
8. Store secrets securely in macOS Keychain.
9. Provide normal authentication when importing credentials is unsupported.
10. Support LAN-only operation.

Never collect or transmit credentials to developer-controlled services.

Never log authentication tokens.

Do not bypass operating-system or service security protections.

## 5.2 Printer Communication

Support available and authorized:

- LAN discovery.
- Cloud connectivity.
- MQTT monitoring.
- Printer status.
- Nozzle temperature.
- Bed temperature.
- Current layer.
- Print progress.
- Remaining-time estimates.
- Error reporting.
- Print upload.
- Print start.
- Pause.
- Resume.
- Cancel.
- Camera access.
- AMS Lite monitoring.

Respect firmware restrictions.

Do not assume undocumented protocols remain stable.

## 5.3 Printer Profiles

Include validated profiles for:

- Bambu Lab A1.
- Supported nozzle sizes.
- Supported build surfaces.
- Compatible filament types.
- AMS Lite configurations.

Use verified printer limits.

Preserve validated startup, shutdown, and filament-change procedures.

---

# 6. MakerWorld Integration

Provide a native MakerWorld browser.

Support, where authorized:

- Model search.
- Categories.
- Sorting.
- Filtering.
- Thumbnails.
- Model previews.
- Model descriptions.
- Available print profiles.
- Model downloading.
- Direct import.
- Direct slicing.
- One-click printing.
- Attribution.
- Licensing information.

Reproduce Bambu Studio's download-to-print workflow as closely as permitted.

Prefer official integration mechanisms.

If a feature requires unavailable proprietary APIs, document the limitation and implement the closest authorized alternative.

Do not fabricate API support.

---

# 7. Additional Model Repositories

Provide an extensible model discovery system.

Support additional repositories through permitted APIs.

Features:

- Unified search.
- License filtering.
- Format filtering.
- Model previews.
- Direct downloads.
- Direct importing.
- Source attribution.
- Download management.

Make MakerWorld the primary integrated experience.

---

# 8. Model Importing and Unit Detection

Support:

- STL.
- OBJ.
- 3MF.
- STEP where technically feasible.
- Other compatible formats supported by reused libraries.

Automatically analyze imported dimensions.

Detect potentially incorrect units:

- Millimeters.
- Centimeters.
- Meters.
- Inches.
- Unitless geometry.

If a model appears unusually large or small, ask whether to convert it to millimeters.

Display:

- Original dimensions.
- Suggested dimensions.
- Conversion factor.
- Preview.

Options:

- Convert.
- Keep original.
- Apply to all selected models.

Never silently change ambiguous dimensions.

Preserve the original model.

---

# 9. Non-Destructive Geometry Architecture

All geometry operations must be reversible.

Maintain an immutable source model and a sequence of transformations.

Example:

Original Model
→ Unit Conversion
→ Orientation
→ Scaling
→ Splitting
→ Connectors
→ Plate Arrangement
→ Slicing

Store operations as editable parameters.

Regenerate derived geometry when parameters change.

Do not accumulate destructive mesh modifications.

Support complete undo and redo.

Preserve source geometry.

---

# 10. Automatic Oversized-Model Splitting

When a model exceeds the printer's usable build volume:

1. Check whether rotation allows it to fit.
2. If not, determine suitable splitting planes.
3. Split the model into printable sections.
4. Generate connectors.
5. Validate section dimensions.
6. Arrange sections across plates.
7. Produce an assembly preview.

Optimize splitting for:

- Minimum section count.
- Minimum plate count.
- Structural strength.
- Surface appearance.
- Assembly simplicity.
- Connector accessibility.
- Print orientation.
- Support requirements.
- Print duration.

Allow manual editing of all cuts.

Do not automatically split an object merely because it is incorrectly scaled.

Resolve ambiguous units first.

---

# 11. Connector System

Provide connector presets including:

- Cylindrical pins.
- Snap-fit cylinders.
- Dovetails.
- Rectangular pins.
- Peg-and-hole joints.
- Puzzle joints.
- Threaded connectors.
- Screw-compatible joints.
- Magnet pockets.
- Custom connectors.

Every connector must support editable:

- Diameter.
- Length.
- Depth.
- Clearance.
- Tolerance.
- Orientation.
- Chamfer.
- Fillet.
- Wall thickness.
- Retention geometry.
- Spacing.
- Quantity.

Support material-aware defaults.

Allow custom presets.

Support individual connector editing.

## 11.1 Reversibility

Provide connector controls:

- Globally.
- Per object.
- Per connector.

Disabling connectors must regenerate geometry without connector modifications.

Re-enabling connectors must restore previous parameters.

Disabling splitting must restore the original unsplit model.

No destructive geometry changes are permitted.

---

# 12. Automatic Multi-Plate Arrangement

Automatically distribute oversized-model sections across plates.

Optimize:

- Plate count.
- Object orientation.
- Support consumption.
- Material grouping.
- Color grouping.
- Print duration.
- Object spacing.

Validate that every section fits.

Maintain relationships between original objects and generated sections.

Allow manual rearrangement.

Provide an assembly diagram.

Support multi-plate project scheduling.

Do not assume automatic physical plate swapping.

---

# 13. Advanced Multicolor Optimization

Develop a sophisticated multicolor optimization system.

Primary objectives:

- Minimize filament changes.
- Minimize purge waste.
- Minimize total filament consumption.
- Minimize print duration.
- Preserve print quality.
- Preserve structural integrity.
- Prevent collisions.

## 13.1 Existing Optimization Techniques

Reuse established implementations where possible.

Support:

- Optimized color sequencing.
- Adaptive purge volumes.
- Flush into infill.
- Flush into supports.
- Flush into eligible internal structures.
- Purge tower optimization.
- Transition-specific purge settings.

Account for asymmetric transitions between filament colors.

## 13.2 Advanced Scheduling

Investigate:

- Region-based color scheduling.
- Independent-region scheduling.
- Safe variable-height region printing.
- Nonplanar scheduling where practical.
- Dependency-aware toolpath ordering.

The objective is to reduce unnecessary filament swaps.

Do not arbitrarily reorder layers.

Any region printed at a different height must pass collision and dependency validation.

## 13.3 Optimization Modes

Provide:

- Off.
- Safe.
- Experimental.

Also provide priorities:

- Fastest.
- Least waste.
- Best quality.
- Balanced.

Experimental algorithms must never bypass safety checks.

---

# 14. Multicolor Optimization Report

Provide a detailed before-and-after comparison.

Compare conventional Bambu Studio or OrcaSlicer slicing against the optimized result.

Report:

- Estimated print duration.
- Filament changes.
- Purge waste.
- Total filament consumption.
- Purge tower consumption.
- Travel distance.
- Filament cost.
- Estimated electricity consumption.
- Total estimated cost.

Display:

- Baseline values.
- Optimized values.
- Absolute differences.
- Percentage improvements.

Provide layer-by-layer visualization.

Show color-transition sequences.

Use identical models, materials, printer profiles, and quality requirements.

Never invent improvements.

If optimization does not provide meaningful benefits, prefer conventional slicing.

---

# 15. Manual Mesh Repair

Mesh repair must be explicitly user-initiated.

Provide a visible:

Repair Model

button.

Automatic diagnostics are permitted.

Automatic source-mesh repair is prohibited.

Importing, slicing, exporting, or changing settings must not silently repair geometry.

## 15.1 Diagnostics

Detect:

- Non-manifold geometry.
- Open boundaries.
- Missing faces.
- Inverted normals.
- Duplicate faces.
- Duplicate vertices.
- Degenerate triangles.
- Self-intersections.
- Disconnected components.
- Invalid topology.

## 15.2 Repair Workflow

When Repair Model is selected:

1. Analyze geometry.
2. Display detected problems.
3. Suggest repairs.
4. Preview modifications.
5. Allow individual repair selection.
6. Apply approved repairs.
7. Validate the result.

Preserve the original model.

Support undo.

Report dimensional and volume changes.

Audit reused slicing libraries for automatic geometry modifications.

Internal processing must not silently overwrite source geometry.

---

# 16. Advanced Geometry Tools

Provide:

- Mesh simplification.
- Surface smoothing.
- Boolean operations.
- Cutting.
- Splitting.
- Merging.
- Flattening.
- Measurement.
- Alignment.
- Clearance analysis.
- Hole analysis.
- Connector placement.
- Object orientation.

Handle large meshes efficiently.

Avoid crashes during high-polygon operations.

Support progress reporting and cancellation.

---

# 17. Intelligent Print Orientation

Evaluate orientations using:

- Strength.
- Surface quality.
- Supports.
- Print time.
- Material consumption.
- Bed adhesion.
- Overhangs.
- Connector placement.

Provide configurable priorities.

Display tradeoffs.

Never overwrite manual orientation without approval.

---

# 18. Intelligent Slicing Profiles

Analyze geometry and recommend:

- Layer height.
- Wall count.
- Infill.
- Support configuration.
- Print speed.
- Cooling.
- Seam placement.
- Bed adhesion.

Support:

- Quality mode.
- Strength mode.
- Speed mode.
- Material-saving mode.
- Balanced mode.

Allow per-object and per-region settings.

Show proposed changes before applying them.

---

# 19. Filament Management

Support:

- PLA.
- PLA+.
- PETG.
- TPU 95A.
- Other printer-compatible materials.

Include third-party filament profiles.

Provide:

- Spool inventory.
- Remaining-filament estimates.
- Filament cost tracking.
- AMS Lite mapping.
- Compatible spool switching.
- Material compatibility checks.
- External spool support.

Do not assume TPU is compatible with AMS Lite.

---

# 20. Calibration

Include established calibration workflows.

Support:

- Flow ratio.
- Pressure advance where supported.
- Temperature towers.
- Retraction.
- Stringing.
- Bed adhesion.
- Dimensional accuracy.
- Hole compensation.
- Connector clearance.
- Overhang performance.

Store calibration results per printer, nozzle, and filament.

Reuse existing OrcaSlicer calibration implementations where practical.

---

# 21. Timelapse and Sequential Printing

Provide independent controls for:

- Timelapse.
- Smooth timelapse.
- Layer-based printing.
- Object-based printing.

Allow timelapse generation to be fully disabled.

Automatically identify incompatible settings.

Provide safe sequential-print ordering.

Validate:

- Toolhead clearance.
- Gantry clearance.
- Object spacing.
- Object height.
- Travel paths.
- Printed geometry.

Reject unsafe arrangements.

---

# 22. Complete Toolpath Simulation

Simulate generated G-code.

Model:

- Toolhead movement.
- Nozzle position.
- Extrusion.
- Travel.
- Printed geometry.
- Layer dependencies.
- Filament changes.
- Purging.
- Sequential printing.
- Build-volume boundaries.
- Collision envelopes.

Account for evolving printed geometry.

Validate experimental toolpaths before printing.

Use conservative safety margins.

Never claim simulation guarantees physical safety.

---

# 23. Camera-Based Print Monitoring

Integrate with the A1 camera where supported.

Detect visually observable:

- Spaghetti printing.
- Detached objects.
- Severe stringing.
- Large filament blobs.
- Warping.
- Failed supports.
- Major layer shifts.
- Missing extrusion.
- Other significant visible failures.

Prefer local inference.

Use Core ML and Metal where beneficial.

## 23.1 Hardware Constraints

Investigate and verify:

- Available camera resolution.
- Accessible frame rate.
- Frame latency.
- Streaming restrictions.
- Firmware compatibility.
- Lighting requirements.
- Camera visibility.

Do not assume high-frame-rate streaming.

Adapt detection algorithms to actual camera capabilities.

Do not claim reliable detection of defects the camera cannot observe.

## 23.2 Detection Modes

Provide:

- Monitor only.
- Pause on confirmed failure.
- Stop on confirmed failure.

Default to Monitor Only.

Require sustained evidence before automatic intervention.

Display confidence and detection regions.

Avoid repeated pause or cancel commands.

## 23.3 Privacy

Process frames locally by default.

Do not upload footage without consent.

Allow monitoring to be disabled.

Make recording optional.

---

# 24. Print Failure Prevention

Analyze models and toolpaths for:

- Floating geometry.
- Unsupported regions.
- Weak bed contact.
- Tall unstable objects.
- Excessively thin walls.
- Unsafe travel.
- Potential collisions.
- Insufficient filament.
- Incompatible materials.
- Invalid temperature settings.

Distinguish definite geometric problems from estimated failure risks.

Offer corrective recommendations.

Do not silently modify models.

---

# 25. G-code to 3MF Reconstruction

Support importing:

- Standard G-code.
- Compatible G-code-containing 3MF archives.

Recover original meshes and metadata when available.

Otherwise reconstruct approximate geometry from extrusion paths.

Analyze:

- Perimeters.
- Infill.
- Supports.
- Extrusion widths.
- Layer heights.
- Filament changes.
- Object boundaries.

Generate editable reconstructed meshes where possible.

Support export to STL, OBJ, and 3MF.

Clearly report reconstruction limitations.

Never claim exact recovery when original geometry is unavailable.

Investigate experimental reconstruction of parametric features such as cylinders, holes, and threads.

---

# 26. 3MF Compatibility and Recovery

Support existing Bambu Studio and OrcaSlicer projects.

Detect:

- Invalid archives.
- Missing meshes.
- Broken references.
- Invalid metadata.
- Unsupported settings.
- Version incompatibilities.

Provide manual recovery tools.

Preserve original files.

Support compatible project migration.

Never silently discard project settings.

---

# 27. Print Cost and Energy Estimation

Calculate:

- Model filament cost.
- Support cost.
- Purge cost.
- Purge tower cost.
- Electricity cost.
- Total print cost.
- Cost per object.
- Cost per plate.
- Cost per project.

Allow configurable filament prices and electricity rates.

Use measured power data where available.

Label estimates clearly.

---

# 28. Print Monitoring and Notifications

Support:

- Print started.
- Print paused.
- Print resumed.
- Print completed.
- Print failed.
- Filament problems.
- Printer disconnected.
- Camera-detected failures.

Provide native macOS notifications.

Allow automatic archiving of generated G-code and project metadata.

Preserve printer security.

---

# 29. Plugin Architecture

Create a secure extension system.

Support plugins for:

- Model repositories.
- File formats.
- Slicing algorithms.
- Optimization algorithms.
- Printer integrations.
- Filament profiles.
- Calibration.
- Camera detection models.

Use explicit permissions.

Do not expose credentials automatically.

Isolate plugins where practical.

Version plugin interfaces.

Prevent plugin failures from corrupting projects.

---

# 30. Performance

Optimize for Apple Silicon.

Use:

- Efficient multithreading.
- Swift Concurrency.
- Metal rendering.
- Incremental updates.
- Cached computations.
- Memory-efficient geometry processing.
- Background operations.

Benchmark against Bambu Studio and OrcaSlicer.

Measure:

- Slicing speed.
- Peak memory usage.
- Rendering performance.
- Large-model performance.
- Project loading time.
- Optimization overhead.

Do not claim performance improvements without measurements.

---

# 31. Deterministic Slicing

Identical inputs, settings, and engine versions should produce reproducible G-code.

Record:

- Application version.
- Engine version.
- Printer profile version.
- Filament profile versions.
- Optimization algorithm version.
- Relevant settings.
- Model hashes.

Support reproducible projects.

Preserve known-good configurations.

Allow rollback.

---

# 32. Safety

Safety is a release-blocking requirement.

Validate:

- Printer limits.
- Movement boundaries.
- Temperature limits.
- Extrusion limits.
- Toolhead clearance.
- Gantry clearance.
- Sequential printing.
- Filament changes.
- Material compatibility.
- G-code structure.
- Firmware compatibility.

Preserve validated printer procedures.

Experimental optimizations must pass appropriate tests.

Never silently disable safety checks.

Physical printer testing is mandatory before declaring safety-critical functionality production-ready.

---

# 33. Security and Privacy

The application must be open source.

Requirements:

- No unnecessary telemetry.
- No developer-controlled credential collection.
- Keychain-based secret storage.
- Explicit network permissions.
- Secure printer communication.
- Safe plugin permissions.
- Local camera processing by default.
- Documented data handling.
- Dependency auditing.
- License compliance.

Respect upstream licenses, including applicable copyleft obligations.

Sign and notarize production releases where practical.

---

# 34. Mandatory Development Documentation

Maintain:

- SPEC.md
- AGENTS.md
- CLAUDE.md
- TODO.md
- ROADMAP.md
- ARCHITECTURE.md
- FEATURE_PARITY.md
- TESTING.md
- BENCHMARKS.md
- SECURITY.md
- HARDWARE_COMPATIBILITY.md
- CHANGELOG.md
- README.md

Documentation must reflect actual implementation status.

Do not mark features complete without verification.

---

# 35. Development Phases

## Phase 0: Research
Audit upstream slicers, licensing, architecture, and hardware compatibility.

## Phase 1: Foundation
Build the native application and integrate an established slicing engine.

## Phase 2: A1 Integration
Implement profiles, connectivity, slicing, and reliable print submission.

## Phase 3: Feature Parity
Implement and validate applicable Bambu Studio functionality.

## Phase 4: Geometry
Implement model editing, unit detection, splitting, connectors, and multi-plate arrangement.

## Phase 5: Online Models
Implement MakerWorld and additional repository integrations.

## Phase 6: Optimization
Implement multicolor scheduling, purge reduction, and benchmarking.

## Phase 7: Intelligence
Implement camera monitoring, orientation optimization, and profile recommendations.

## Phase 8: Production
Complete regression testing, hardware validation, security auditing, and release packaging.

Do not attempt every phase in one coding session.

---

# 36. Development Workflow

Before each task:

1. Read AGENTS.md.
2. Review TODO.md.
3. Inspect relevant source code.
4. Identify reusable implementations.
5. Define acceptance criteria.
6. Implement the smallest complete change.
7. Run relevant tests.
8. Review the result.
9. Update documentation.
10. Create a Git commit after verification.

Keep tasks independently testable.

Do not combine unrelated work.

Do not mark untested features complete.

---

# 37. Git Requirements

Use Git from the beginning.

Create a commit after every verified, coherent task or feature.

Requirements:

- Small, focused commits.
- Descriptive commit messages.
- No credentials in commits.
- No unnecessary generated files.
- No unrelated modifications.
- No destructive repository operations without justification.
- Maintain a working main branch.
- Preserve rollback points.

Commit only after required tests pass.

If testing is blocked, record the blocker rather than falsely marking the task complete.

---

# 38. Testing and Verification

Implement:

- Unit tests.
- Integration tests.
- Regression tests.
- Performance benchmarks.
- Differential slicing tests.
- Geometry validation.
- G-code validation.
- Hardware tests.

Compare against pinned versions of Bambu Studio and OrcaSlicer.

Test:

- Small models.
- Oversized models.
- Incorrect units.
- Invalid STL files.
- Multicolor prints.
- AMS Lite operations.
- TPU workflows.
- Sequential printing.
- Connector generation.
- Multi-plate projects.
- G-code reconstruction.
- Camera monitoring.

Never fabricate test results.

---

# 39. Definition of Done

A task is complete only when:

1. Implementation exists.
2. The project builds.
3. Relevant tests pass.
4. Existing functionality remains intact.
5. Acceptance criteria are satisfied.
6. Documentation is updated.
7. Safety implications are reviewed.
8. A coherent Git commit is created.

Hardware-dependent functionality must remain marked as awaiting hardware validation until tested on appropriate hardware.

---

# 40. Final Project Requirements

The finished application must:

- Launch natively on Apple Silicon.
- Provide a polished SwiftUI interface.
- Slice real models.
- Produce validated A1-compatible G-code.
- Support AMS Lite.
- Integrate with Bambu Lab printers through supported methods.
- Provide native MakerWorld workflows.
- Support complete applicable Bambu Studio feature parity.
- Automatically identify oversized models.
- Support reversible splitting and connectors.
- Automatically distribute sections across plates.
- Provide manual mesh repair.
- Support advanced multicolor optimization.
- Produce quantitative optimization reports.
- Support safe sequential printing.
- Allow timelapses to be disabled.
- Provide camera-based failure monitoring.
- Support G-code-to-3MF reconstruction.
- Maintain reproducible slicing.
- Pass relevant automated and physical validation.

The application must remain reliable even when experimental features are disabled.

The established slicing engine must remain available as a conventional fallback.

Do not claim full completion until the corresponding acceptance criteria have been verified.

# FINAL DIRECTIVE

Begin with source-code research, architecture planning, licensing verification, and repository documentation.

Create TODO.md before implementing application features.

Break the project into small, independently testable tasks.

Reuse existing slicer implementations wherever possible.

Prefer minimal, correct, maintainable code.

Implement incrementally.

Verify every completed task.

Create a Git commit after each verified, coherent change.

Maintain accurate documentation.

Never fabricate implementation status, benchmark results, compatibility, or safety validation.

The objective is a production-quality native macOS slicer that preserves Bambu Studio functionality while providing meaningful improvements in usability, performance, model preparation, and multicolor printing.