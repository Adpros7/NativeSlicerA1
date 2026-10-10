# Session State

## Current phase
Phase 1: Application Foundation (Phase 0 complete). P1-003 (slicing engine
integration) in progress — real `libslic3r` built from vendored BambuStudio
source; C-ABI bridge linking in progress.

## Last completed task
P1-006: Transform/UndoStack/SceneObject (reversible transform history).

## Current task / progress — P1-003 Integrate established slicing engine
- Built `libslic3r` (BambuStudio's real slicing core) as a native arm64
  static lib from `.research/BambuStudio` (gitignored local clone):
  - Patched the upstream `deps/CMakeLists.txt` deployment-target FORCE
    (10.15 → 14.0; 10.15 is rejected by the current Xcode's libc++).
  - Built the full `deps` target (Boost, CGAL, OCCT, OpenCV, Assimp, TBB,
    wxWidgets, FFmpeg, etc. — ~4.7GB, 25 external projects, all succeeded).
  - Configured BambuStudio's own CMake project against those deps and
    built the `libslic3r` target directly (not the whole GUI app):
    `liblibslic3r.a` (250MB) + `liblibslic3r_cgal.a` (32MB), zero errors.
- Writing `Sources/CSlic3rBridge/` — a C-ABI shim
  (`nsa1_stl_triangle_count`) that calls `Slic3r::TriangleMesh::ReadSTLFile`
  directly, proving Swift can link and call into the real engine (not a
  hand-rolled parser) before building out the full STL/3MF import path.
- Link graph is large and only resolvable correctly via CMake (hand-picking
  `-l`/`-L` flags doesn't scale — tried, abandoned). Current approach:
  added a throwaway `bridge_poc/` CMake subdirectory inside the vendored
  checkout (`add_subdirectory(bridge_poc)` in BambuStudio's top-level
  CMakeLists.txt, NOT committed to our repo — lives only in `.research/`)
  that links `bridge_poc` against the `libslic3r` CMake target so CMake
  resolves the full transitive static-lib/framework graph for us. Goal:
  get a working link command from CMake's `link.txt`, then replicate those
  flags in `Package.swift`'s `linkerSettings` for the real
  `CSlic3rBridge` SwiftPM target.
- Found along the way: `libslic3r`'s `LogSink.cpp` (cloud log upload/
  encryption) references `Slic3r::Http` and `Slic3r::BBL_Encrypt`, which
  are actually implemented in `src/slic3r/Utils/` (the GUI/app layer, not
  `libslic3r` itself) — an upstream architecture leak. Added those two
  `.cpp` files directly to the POC target to resolve it (not a long-term
  fix; the real fix is likely a CMake option to disable cloud logging, or
  just always including these two small files alongside libslic3r since
  we don't want Bambu's telemetry upload anyway).
- Caution: editing `bridge_poc/CMakeLists.txt` and re-running `cmake .`
  has twice triggered a full `libslic3r` recompile (CMake reconfigure
  side-effect from adding `find_package(OpenSSL/CURL)` — not yet
  understood why). Each full rebuild takes ~100-110s. Avoid unnecessary
  reconfigures; batch CMakeLists.txt changes.

## Important technical decisions
- Repo licensed AGPLv3 (RESEARCH.md P0-004) to permit `libslic3r` reuse.
- Build system: SwiftPM (`Package.swift`), not `.xcodeproj`.
- `libslic3r` is NOT vendored into our git repo — it's a local build
  artifact produced from the gitignored `.research/BambuStudio` checkout.
  Decision needed before this becomes a real dependency: either (a) commit
  a build script that re-clones+builds BambuStudio and produces the
  static libs as part of our own build process (reproducible, but a ~2-5
  min first-time cost and ~5GB disk), or (b) vendor just the needed
  `libslic3r` *source* subset into our repo under its own AGPLv3 notice
  and build it directly via our own CMake, dropping BambuStudio's GUI/app
  layer entirely. Leaning (b) once the link graph is fully understood —
  avoids the LogSink/Http leak and the wxWidgets/FFmpeg/OpenCV build cost
  entirely (profiling shows `libslic3r` core doesn't need FFmpeg/wx, only
  CGAL/OCCT/OpenCV/Assimp/Boost — see RESEARCH.md update needed).
- Swift/C++ interop: C-ABI shim (`CSlic3rBridge`), not Swift's native C++
  interop — libslic3r's heavy template/Boost-heavy headers would be a poor
  fit for the Swift C++ importer; a C boundary is simpler and matches
  ARCHITECTURE.md's documented fallback.

## Uncommitted changes
None in the git repo itself — `Sources/CSlic3rBridge/` exists on disk but
is a work-in-progress (not yet linking); will commit once the POC proves
the full link line and `CSlic3rBridge` is wired into `Package.swift` and
passes a real `swift build`.

## Known blockers
None hard-blocking; link graph is large but converging (most of OCCT/
Boost/CGAL resolved automatically via CMake; down to a handful of
upstream-architecture-leak symbols).

## Next recommended action
1. Let the current `bridge_poc` CMake build finish; read
   `build/arm64/bridge_poc/CMakeFiles/bridge_poc.dir/link.txt` for the
   golden link command.
2. Translate that into `Package.swift` `linkerSettings` (`.unsafeFlags`)
   for a `CSlic3rBridge` target; add the target’s `.cpp`/header.
3. Smoke-test: `swift build` + `swift run` a throwaway call to
   `nsa1_stl_triangle_count` against a real STL (e.g. `bbl-3dp-logo.svg`'s
   sibling `bbl-3dp-A1M.stl` resource already vendored under
   `Resources/Profiles/BBL`, or any system/test STL).
4. Decide (a) vs (b) above for how `libslic3r` gets built as part of this
   project's own build (not just this one-off `.research` checkout).

## Relevant test/build commands
- `swift build` / `swift test` / `swift run NativeSlicerA1`
- Engine checkout: `.research/BambuStudio` (gitignored); deps built at
  `.research/BambuStudio/deps/build/arm64/BambuStudio_deps`; engine build
  tree at `.research/BambuStudio/build/arm64`.
