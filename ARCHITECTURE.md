# Architecture Decisions

## P0-005: Swift/C++ interoperability

Toolchain: Xcode 27 / Swift 6.4 — supports native bidirectional C++ interop
(`SwiftSettings: .interoperabilityMode(.Cxx)` in SwiftPM, or
`SWIFT_OBJC_INTEROP_MODE = objcxx` in Xcode build settings).

Decision: use Swift's built-in C++ interop to call `libslic3r` directly.
Skip a hand-written Objective-C++ bridging layer (AGENTS.md: avoid custom
frameworks / unnecessary abstraction) except where Swift's importer cannot
represent a construct (heavy template metaprogramming, non-copyable types
with custom destructors it misimports, `boost::` types at API boundaries).
For those specific cases, add a thin `extern "C"` C shim function per call,
not a general-purpose wrapper layer.

Build shape:
- `libslic3r` compiled as a static library target via its existing CMake
  build (reuse Bambu's CMake, do not port to SwiftPM/Xcode build system).
- Xcode project links the static lib; a small Swift package target
  (`SlicingEngineBridge`) exposes a minimal C++/C API surface Swift imports
  directly.
- SwiftUI/AppKit layer never touches `libslic3r` types directly except
  through this bridge target.

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
