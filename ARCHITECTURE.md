# Architecture Decisions

## P0-005 / P1-003: Swift/C++ interoperability (updated with real outcome)

**Original plan** (below, superseded): use Swift's native bidirectional
C++ interop to call `libslic3r` directly.

**What actually happened, proven by a working build+test:** Swift's
native C++ interop was not used. `libslic3r`'s headers are saturated with
Boost (`boost::optional`, `boost::filesystem`, `boost::log`), heavy
template metaprogramming (Eigen, CGAL, libnest2d), and macro-heavy config
code that Swift's C++ importer cannot represent cleanly. Built and proved
a **C-ABI bridge** instead (`Sources/CSlic3rBridge/`):

- `CSlic3rBridge.h` / `.cpp`: `extern "C"` functions only, each taking/
  returning POD types or `const char *`. First function:
  `nsa1_stl_triangle_count(const char *path) -> int64_t`, calling
  `Slic3r::TriangleMesh::ReadSTLFile` directly.
- SwiftPM `.target(name: "CSlic3rBridge", ...)` compiles this against the
  real `libslic3r` headers (vendored at `vendor/BambuStudio/`, built by
  `Scripts/build-libslic3r.sh`); the executable target links the ~88
  resulting static libs (libslic3r, CGAL, OCCT, Boost, Assimp, OpenCV,
  TBB, etc.) via `linkerSettings: [.unsafeFlags([...])]` in `Package.swift`,
  computed from CMake's actual link graph for a throwaway
  `nsa1_bridge_test` executable (hand-picking `-l`/`-L` flags does not
  scale for a dependency graph this size — let CMake resolve it, then copy
  the resulting flags).
- Verified end-to-end: `SlicingEngineBridgeTests.testParsesRealSTLViaRealEngine`
  calls `SlicingEngine.stlTriangleCount(atPath:)` from pure Swift against a
  real vendored STL file and gets the correct real answer (1016 triangles),
  with libslic3r's own logging (`Initializing StaticPrintConfigs`) visible
  in the test output as independent proof of real linkage.
- One upstream wrinkle found and worked around: `libslic3r`'s
  `LogSink.cpp` (cloud log upload/encryption) references `Slic3r::Http`
  and `Slic3r::BBL_Encrypt`, which are actually implemented in
  `src/slic3r/Utils/` (the GUI/app layer, not `libslic3r` itself) — an
  upstream architecture leak. Worked around by compiling those two small
  files into a `nsa1_libslic3r_leak_shim` static lib alongside `libslic3r`
  (see `Scripts/build-libslic3r.sh`), rather than disabling cloud logging
  or forking `libslic3r`.

Still true from the original plan: SwiftUI/AppKit never touches
`libslic3r` types directly, only through this bridge target (now a C-ABI
target, not a native-interop one).


## P0-006: Metal rendering architecture

Standard MetalKit integration, no third-party rendering engine:
- `MTKView` wrapped via `NSViewRepresentable` for SwiftUI embedding.
- A `Renderer: NSObject, MTKViewDelegate` owns the `MTLDevice`,
  `MTLCommandQueue`, pipeline states, and scene buffers.
- Mesh data (triangles from imported STL/3MF, sliced G-code toolpaths)
  converted from `libslic3r`'s `TriangleMesh`/`TriangleMesh3D` into Metal
  vertex buffers at import/slice time, not per-frame.
- Camera/orbit controls: implement directly (arcball math is ~100 lines,
  not worth a dependency — ponytail: skip a gesture/camera framework).

## P0-012: Application architecture (finalized)

```mermaid
graph TD
  UI[SwiftUI Views] --> VM[Observable App State / ViewModels]
  VM --> Bridge[SlicingEngineBridge (Swift/C++ interop)]
  Bridge --> Core[libslic3r static lib - AGPLv3, reused from BambuStudio]
  VM --> Renderer[Metal Renderer]
  Renderer --> Core
  VM --> Net[Printer Communication - Swift, ported from slic3r/Utils]
  VM --> Persist[Project Persistence - Swift, Codable + 3MF]
  VM --> Auth[Keychain-backed Auth]
```

Layer boundaries (AGENTS.md section 5):
- UI never calls `libslic3r` or networking directly; always through
  ViewModels.
- `SlicingEngineBridge` is the only module with C++ interop enabled —
  isolates upstream modification surface per AGENTS.md section 4.
- Printer communication (A1 LAN/MQTT/FTP) reimplemented in Swift (not C++
  interop) once protocol details are confirmed from BambuStudio's
  `slic3r/Utils/` source — small enough surface area that a native Swift
  networking stack (URLSession + a minimal MQTT client) beats bridging
  wxWidgets-era C++ networking code.

## P0-013: Build and testing infrastructure

- Xcode project (`NativeSlicerA1.xcodeproj`) as primary build; `libslic3r`
  built via CMake as a pre-build script phase producing a static lib the
  Xcode project links.
- Unit tests: XCTest for Swift layers; reuse `libslic3r`'s existing C++ test
  suite (`tests/` in BambuStudio) unmodified for the slicing core — do not
  duplicate upstream test coverage.
- CI: deferred until P1 foundation exists (no code to test yet).
