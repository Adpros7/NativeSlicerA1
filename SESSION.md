# Session State

## Current phase
Phase 1: Application Foundation — complete (P1-001 through P1-009). Phase 0
and Phase 9 docs complete; Phase 2 partially complete. Next unblocked:
P2-004 (print upload) or P2-007 (validate printer-specific G-code) — both
hardware-adjacent and not hardware-verifiable this session; alternatively
Phase 3 (feature parity) work can start.

## Last completed task
P1-009: G-code visualization. Real per-move toolpath extraction from the
engine's own `GCodeProcessorResult` (previously discarded by P1-008),
rendered as a GPU line-list through a dedicated Metal pipeline, wired to a
toolbar "Slice" button. Committed and pushed (see `git log`).

## Current task / progress
No task in progress.

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
  column-major transform). Metal buffers are built once per mesh and cached;
  only per-object uniforms are encoded each frame. Project replacement is
  transactional: a failed load retains the open scene.
- **Conventional slicing (P1-008)**: `nsa1_slice_to_gcode` (CSlic3rBridge)
  builds a `Slic3r::Model` from placed scene objects, seeds
  `DynamicPrintConfig::full_print_config()`, overlays A1 profile fields
  resolved by `BambuProfileLoader` (via `SlicingJob.resolvedConfigEntries`,
  serialized to libslic3r's own comma-joined array string format), then
  calls `Print::apply`/`validate`/`process`/`export_gcode`. **Upstream bug
  worked around**: `full_print_config()`'s cloned `coEnum`/`coEnums`
  defaults have a null `keys_map` (only `create_default_option()` wires it
  up); null-derefs on `deserialize()`/`serialize()`. Fixed with a repair
  pass copying `ConfigOptionDef::enum_keys_map` onto any option instance
  (both `ConfigOptionEnumsGeneric` and the nullable variant) missing it,
  run immediately after seeding, before any overrides. Diagnosed via
  `lldb` crash backtraces (frame unwinding needed a full `bt` on the
  stopped process via `-s <script>`, not `-o` batch commands, to get past
  frame 0 in the optimized static lib). **Known gap**: the per-nozzle
  `"include"` key (custom start/end/layer-change G-code templates) isn't
  resolved by `BambuProfileLoader` — only `inherits` chains are — so
  slicing currently uses the engine's own default G-code templates, not
  the A1-specific ones.
- **G-code visualization (P1-009)**: `Print::export_gcode`'s
  `GCodeProcessorResult::moves` (real per-move toolpath data, already
  computed internally, previously discarded) is now returned through
  `nsa1_slice_to_gcode`'s optional `NSA1Toolpath**` out-param as flat
  line segments (consecutive `Extrude`/`Travel` move positions; broken at
  non-move events like retract/seam/tool-change). `MetalRenderer` gained a
  second compiled pipeline (`toolpath_vertex`/`toolpath_fragment`) drawing
  this as a GPU line-list (extrude orange, travel gray). `ProjectDocument
  .slice()` runs the real pipeline via `Task.detached` off the
  `@MainActor` (so the UI stays responsive) and is wired to a toolbar
  "Slice" button in `ContentView`. **Known gap**: only the default A1/PLA
  profile selection is used — no per-slice profile picker UI yet.
- Printer networking (A1 discovery/MQTT): reimplemented natively in Swift
  from reverse-engineered protocol docs — Bambu's own implementation is
  closed-source (`bambu_networking` plugin, no public source). Not
  hardware-verified against a real printer (see TODO.md P2-002/003/006).

## Uncommitted changes
None after this session's commits (P1-008, P1-009).

## Known blockers
None. Open follow-ups (not blocking, tracked in TODO.md):
- P1-008's `"include"` custom G-code template gap.
- P1-009's lack of a profile-selection UI (defaults to A1 0.4 nozzle /
  0.20mm Standard / Generic PLA).
- P0-011 feature-parity matrix needs a file:line citation pass (currently
  a 274-row draft without per-row sourcing).
- THIRD_PARTY_LICENSES.md has a few "📋 public record, not re-verified"
  rows (Boost, CGAL, OCCT, Assimp, OpenCV, TBB, NLopt, FreeType, GMP,
  MPFR, curl, OpenSSL, expat, libjpeg-turbo, libpng, zlib, CocoaMQTT) —
  verify against the exact vendored LICENSE files before any distribution
  decision. CGAL's dual GPL/LGPL licensing specifically needs scoping to
  the exact CGAL packages `libslic3r_cgal` links.
- No hardware A1/AMS Lite available to this session — all printer-facing
  code is protocol/documentation-level verified only.

## Next recommended action
Phase 1 (Application Foundation) is complete. Next unblocked work:
- P2-004/P2-007/P2-008: print upload, printer-specific G-code validation,
  physical A1 validation — all need real hardware, not available this
  session; can implement the upload protocol (P2-004, likely FTP-over-TLS
  per RESEARCH-P0-007.md) without hardware, tested against a local server
  the same way P2-003's MQTT client was tested against a local broker.
- Or start Phase 3 (feature parity): P3-003 (advanced slicing settings)
  is a natural next step that also closes P1-009's profile-picker gap.

## Relevant test/build commands
- `Scripts/build-libslic3r.sh` — one-time/idempotent engine build.
- `swift build` / `swift test` / `swift run NativeSlicerA1`.
- `swift test --filter ProjectDocumentTests` — real 3MF geometry/transform
  round-trip plus failed-load preservation.
- `swift test --filter MetalRendererTests` — real mesh upload/draw and
  real toolpath upload/draw through the compiled GPU pipelines.
- `swift test --filter SlicingJobTests` — real end-to-end G-code
  generation through the A1 profile closure.
