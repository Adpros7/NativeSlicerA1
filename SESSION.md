# Session State

## Current phase
Phase 1: Application Foundation (Phase 0 complete).

## Last completed task
P1-001: SwiftUI skeleton app created (`Sources/NativeSlicerA1/`), builds via
`swift build`, launches as a live process (smoke-verified), `swift test`
passes with wiring smoke test.

## Current task / progress
None in progress. Next unblocked: P1-002 (Metal viewport).

## Important technical decisions
- Repo licensed AGPLv3 (see RESEARCH.md P0-004) to permit reuse of
  `libslic3r` from BambuStudio/OrcaSlicer — both upstream projects are
  AGPLv3. This is a load-bearing decision: distributing this app requires
  AGPLv3 source availability obligations.
- Build system: Swift Package Manager (`Package.swift`), not a hand-authored
  `.xcodeproj`. `libslic3r` will be built via its existing CMake build and
  linked in as a static lib target when P1-003 starts (not yet wired).
- Swift/C++ interop: use Swift 6.4's native bidirectional C++ interop to
  call `libslic3r` directly; thin `extern "C"` shims only where the
  importer can't represent a construct. See ARCHITECTURE.md.
- Metal rendering: MetalKit `MTKView` via `NSViewRepresentable`, no 3rd
  party rendering engine (ARCHITECTURE.md).
- Printer networking (A1): reimplement natively in Swift rather than bridge
  BambuStudio's wx-era C++ networking code — small surface area once
  protocol is known (RESEARCH-P0-007.md: MQTT/TLS 8883, FTPS 990, mDNS
  discovery).
- MakerWorld: external-browser handoff (OrcaSlicer's pattern), not an
  embedded webview against undocumented Bambu endpoints — ToS risk
  (RESEARCH-P0-009.md).

## Uncommitted changes
None — all work through P1-001 is committed and pushed to
`origin/master` (https://github.com/Adpros7/NativeSlicerA1).

## Known blockers
None currently. Open risk (not blocking): AGPLv3 copyleft constrains any
future closed-source distribution plan — flagged in RESEARCH.md P0-004,
no owner decision overriding it yet.

## Next recommended action
P1-002: Implement Metal viewport. Add an `MTKView`-backed SwiftUI view,
wire a minimal `Renderer: MTKViewDelegate` that clears the screen and draws
nothing yet (prove the Metal pipeline before feeding it real mesh data from
P1-004/P1-006). Then P1-003 (vendor `libslic3r` as a CMake-built static lib
and wire the Swift/C++ interop bridge target) can proceed in parallel since
it touches a different part of the build graph.

## Relevant test/build commands
- `swift build` — compile the app.
- `swift test` — run XCTest suite.
- `swift run NativeSlicerA1` — launch the app (smoke test the UI surface).
- Upstream source for reference: `.research/BambuStudio`, `.research/OrcaSlicer`
  (gitignored shallow clones, re-clone if missing — see RESEARCH.md for
  clone source).
