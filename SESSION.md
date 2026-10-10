# Session State

## Current phase
Phase 1: Application Foundation (Phase 0 and Phase 9 docs complete; Phase 2
partially complete). Next unblocked: P1-007 (project persistence) or
wiring a `LoadedMesh` into the Metal viewport (first real rendering
milestone).

## Last completed task
P1-005: Real 3MF import via `load_3mf` (CSlic3rBridge), tested against a
genuine engine-generated round-trip fixture.

## Current task / progress
None in progress — clean stopping point, everything committed and pushed.

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
- Printer networking (A1 discovery/MQTT): reimplemented natively in Swift
  from reverse-engineered protocol docs — Bambu's own implementation is
  closed-source (`bambu_networking` plugin, no public source). Not
  hardware-verified against a real printer (see TODO.md P2-002/003/006).

## Uncommitted changes
None. All work through P1-005 is committed and pushed to
`origin/master` (https://github.com/Adpros7/NativeSlicerA1).

## Known blockers
None. Open follow-ups (not blocking, tracked in TODO.md):
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
Pick one:
1. **P1-007 (persistence)**: reuse libslic3r's own 3MF reader/writer
   (`load_3mf`/`store_3mf`, already bridged) as the project file format
   rather than inventing a separate JSON format — reuse-first priority +
   BambuStudio/OrcaSlicer precedent both point to `.3mf`. Needs a
   `nsa1_store_3mf` bridge function (write side) to pair with the
   existing read side.
2. **Metal viewport wiring**: feed a `LoadedMesh` (from P1-004/P1-005)
   into `MetalViewport`/`MetalRenderer`'s vertex buffers — currently the
   viewport only clears the background; this is the first real rendering
   milestone (see ARCHITECTURE.md P0-006).
3. **P1-008 (conventional slicing)**: the real next-hardest engine-bridge
   extension — wrap `Slic3r::Print`/`BackgroundSlicingProcess` to
   actually run a slice and emit G-code. Expect a similarly-sized link
   graph/include-order investigation as P1-003 took.

## Relevant test/build commands
- `Scripts/build-libslic3r.sh` — one-time/idempotent engine build.
- `swift build` / `swift test` / `swift run NativeSlicerA1`.
- `swift test --filter SlicingEngineBridgeTests` — fastest way to confirm
  the engine bridge still links and works after a `vendor/` rebuild.
