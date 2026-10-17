# Session State

## Current phase
Phase 1 and Phase 4 (except conditional P4-002 repair) are complete.
Phase 5 is **not complete**: MakerWorld has only an intentionally safe
trusted-browser handoff; a real MyMiniFactory integration exists
alongside it (search/OAuth/download), itself not live-verified
(Cloudflare + packaging blockers). Phase 6 is **complete for everything
verifiable without hardware/OrcaSlicer**. The user-requested **Phase 6.5
(Native Slicer Usability)** is **complete**: always-visible build
plate/grid/axes, real sidebar, Prepare/Preview/Device workflows, a real
Device backend, and a critical production-blocking bug fix (below).
Printer connectivity backend (P2-004/P2-005, FTPS/status/controls) is
implemented; Device-workflow UI consumes it. **Phase 7 is complete for
everything verifiable without hardware** (P7-001 camera client is real
and protocol-tested but not hardware-verified, same gate as P2-002/
P2-003; P7-007 is accurately scoped as partial — toolpath reconstruction
only, not a `.3mf` writer).

## Last completed task
Phase 7, plus Phase 6.5 usability milestone and the P2-004/P2-005
connectivity backend they depend on:

- **Phase 7 (this pass):** researched the real documented A1/P1 chamber
  camera protocol (`OpenBambuAPI/video.md`, byte-exact — port 6000,
  80-byte auth packet, 16-byte frame header + JPEG) rather than leaving
  P7-001 as a fabricated "proprietary, unimplementable" blocker.
  `CameraStreamClient.swift` implements it on the same `Network.framework`
  TLS pattern as `FTPSUploader`; byte-exact unit tests plus a real local
  TLS integration test (`CameraStreamClientIntegrationTests`) prove the
  full handshake→auth→frame round trip. `DeviceSessionModel` adds real
  local-failure detection from the live MQTT status stream (P7-002), a
  real `UNUserNotificationCenter` alert (P7-003), and an explicit
  opt-in auto-pause (P7-004, off by default). `ProjectDocument.
  autoOrientSelection()` finally wires the already-implemented
  `SlicingEngine.autoOrientMesh` (P4-010) to a UI button (P7-005) — it
  had no entry point at all before. `OptimizationReport.recommendations`
  (P7-006) derives tips strictly from the report's own already-real data
  (tool changes, collision, purge volume), never a generic tip.
  `nsa1_load_gcode_toolpath`/`SlicingEngine.loadGCodeToolpath` (P7-007)
  loads an existing `.gcode` via the real `GCodeProcessor` for Preview —
  accurately scoped as partial, since it does not write a `.3mf` back
  out (same project-3MF-with-embedded-G-code gap as Device's "start a
  new print"). **Bug caught during this work:** the new bridge function
  crashed with SIGSEGV on a missing file (no existence check before
  calling into the engine) — fixed with an explicit
  `std::filesystem::exists` guard; `GCodeLoadTests` pins both the
  success and the clean-failure path. 9 new regression tests.

**Previously completed (Phase 6.5 usability + connectivity backend):**

- **Connectivity backend:** `FTPSUploader.swift` — real implicit-FTPS
  client on `Network.framework` (TLS connect → `USER`/`PASS`/`TYPE I`/
  `PASV`/`STOR`), verified against a real local `NWListener` TLS FTP test
  server (self-signed fixture identity, exact command sequence, exact
  uploaded bytes asserted — `FTPSUploaderIntegrationTests`).
  `PrinterStatus.swift` — `PrintStatusReport` parses the real documented
  `device/{serial}/report` schema; `pausePrint`/`resumePrint`/
  `stopPrint`/`startPrint` convenience commands on `PrinterConnection`.
- **Always-visible build plate:** `BuildPlateGeometry.swift` (pure,
  tested) + `MetalRenderer` draws it unconditionally via the existing
  line pipeline — no new shader.
- **Critical bug found and fixed while verifying the plate live:**
  `Camera`'s orbit math treated world **Y** as vertical while every
  mesh/toolpath/plate vertex the engine emits uses **Z** as height — the
  new flat plate rendered as a vertical wall (caught via direct
  window-ID screenshot, not glossed over). Fixed by orbiting around
  world Z (`Camera.swift`); this also corrects how every *pre-existing*
  mesh/toolpath/cut-plane render was oriented — a real, previously
  undetected rendering bug, not something this session introduced but
  something it finally surfaced and fixed.
- **Sidebar:** `SidebarView.swift` — real printer/filament/process
  summary (reads `document.profileSelection` directly) + object list
  with a real empty state.
- **Prepare/Preview/Device workflow:** `SlicerWorkflow` enum +
  `ContentView`'s detail switch; toolbar reorganized (Import/Arrange/
  Slice/Export/Optimization Report always visible; secondary items under
  "More") — confirmed live that the pre-change toolbar actually
  overflowed (Optimization Report/MakerWorld/MyMiniFactory behind a `»`
  chevron at 1500pt) and that the reorganized one does not, down to
  900pt.
- **Device workflow:** `DeviceSessionModel.swift`/`DeviceView.swift` —
  real SSDP discovery, real MQTT connect, real parsed status, real FTPS
  upload. "Start a new print" is intentionally absent: the printer's
  `project_file` command needs a project-3MF with G-code embedded in
  `Metadata/plate_1.gcode` (BambuStudio's separate `Format/bbs_3mf.cpp`
  format, never ported here) — documented, not silently faked.
- **Previously-missing real actions added:** `ProjectDocument.
  arrangeActivePlate()` and `exportGCode(to:)` — `autoArrangeActivePlate`
  already existed but had **no UI entry point at all**; there was no
  G-code export action of any kind.
- **CRITICAL production bug found and fixed:** `ProjectDocument.slice()`
  (and the new `refreshOptimizationDetails()`) ran the real engine via
  `Task.detached`, which **hung forever**. This was reproduced against
  the actual compiled app binary, not just a test: an env-var-triggered
  probe (`NSA1_SLICE_PROBE=1 .build/out/Products/Debug/NativeSlicerA1`)
  imported a mesh and called `slice()`, and it never returned — proving
  the Slice button itself had never actually been exercised end-to-end
  before (every prior test called the engine synchronously, bypassing
  this path). Replacing `Task.detached` with `DispatchQueue.global` did
  **not** fix it — same hang. Root cause is still open (TBB global
  thread pool / Boost static init expecting main-thread first-touch are
  the leading candidates — tracked as **P2-009**). The fix that actually
  works: run `slice()`/`refreshOptimizationDetails()` **synchronously on
  MainActor**, exactly like the already-proven `calibrate()` already
  does — this freezes the UI for the slice's duration (same accepted
  tradeoff `calibrate()` already had) instead of hanging forever.
  Regression test: `ProjectDocumentExportArrangeTests.
  testExportGCodeCopiesRealSlicedBytesAfterSlice` calls `document.
  slice()` directly and reproduces the old hang/crash.
- 18 new regression tests (`BuildPlateGeometryTests`,
  `ProjectDocumentExportArrangeTests`, `ContentViewTests`,
  `PrintStatusReportTests`, `PrinterConnectionCommandTests`,
  `FTPSUploaderTests`, `FTPSUploaderIntegrationTests`); full suite
  144→172 tests, 0 failures, run multiple times for stability per the
  toolchain-sensitivity rule below.
- Live-screenshot-verified (direct window-ID capture via
  `screencapture -l<id>`, which bypasses this environment's heavy
  desktop focus contention — a real environment constraint discovered
  this session, documented below) at compact (900pt), standard
  (1200–1500pt), and wide (1800pt) widths, and in all three workflow
  tabs, in dark mode. Light mode not independently screenshotted — every
  new view uses only system semantic colors/materials, no hardcoded
  colors, so it inherits the same automatic light/dark adaptation the
  rest of the app already relies on.

## NEW finding: this environment's desktop has real, uncontrollable focus contention
`osascript activate` + `screencapture -x` (full-screen capture) is
**not reliable** here — other foreground apps/games on this shared
desktop steal focus between the `activate` call and the capture, and
synthetic mouse clicks go to whatever is actually on top on screen
(real input events, not logical-focus-aware) — menu/button clicks via
screen coordinates cannot be trusted. **Fix:** resolve the target
window's `CGWindowID` via `CGWindowListCopyWindowInfo` (a tiny inline
`swift -e` script, no new dependency) and capture with
`screencapture -l<id> -o`, which reads directly from the window
server's backing store regardless of z-order/focus. Use this for all
future GUI screenshot verification in this environment.

## IMPORTANT finding (still applies): a real, reproduced, bisected toolchain/binary-layout sensitivity
While implementing P4-008's plate-id 3MF persistence, merely adding an
unused parameter to `SlicingEngine.storeThreeMF`'s Swift signature made
an UNRELATED, already-passing test fail deterministically across the
full suite while staying 100% green in isolation. Rigorously bisected.
Root cause not fully understood. Fixed by keeping `storeThreeMF`'s
signature byte-identical and adding new functionality via a WHOLLY
SEPARATE function instead — this pattern was followed again for P4-013's
`sliceToGCodeWithModifiers`. **Any future change to an existing hot-path
C-ABI function's signature should re-run the full suite 3-5× before
trusting a clean result; prefer adding a new sibling function instead.**
Confirmed again this session: every P6-001/003/005 commit added a new
sibling C-ABI function or new fields on an existing output struct, never
changed an existing function's parameter list — ran the full suite 3-5×
after each regardless.

## Important technical decisions
- **MakerWorld integration is browser-delegated, not embedded** — a
  deliberate, user-confirmed scope boundary (asked via the `ask` tool
  given TODO.md's own explicit licensing-risk flag), not a technical
  limitation worked around. Any future MakerWorld work must stay within
  this boundary (no embedded webview, no reverse-engineered API calls,
  every URL gated through `MakerWorldLinks.isTrusted`).
- **New C-ABI functionality goes in sibling functions, not new
  parameters on existing ones** (P4-008/P4-013 finding above).
  `build_model_from_objects` (C++-internal, non-`extern "C"`) is the one
  exception since it never crosses the Swift/C ABI boundary directly.
- **`ModelVolumeType::PARAMETER_MODIFIER` + per-volume `ModelConfig` is
  sufficient for real local overrides** — confirmed via source
  investigation before writing code, proven via a real extrusion
  comparison test.
- **Two different 3MF formats exist in the vendored engine**:
  `Format/3mf.cpp` (legacy, used throughout) vs. `Format/bbs_3mf.cpp`
  (BambuStudio's separate full project format, not used here — this is
  also why the Device workflow cannot "start a new print": that needs
  the latter format's G-code-embedding, which this app doesn't write).
- **Never call into the vendored engine from a background thread**
  (`Task.detached`/`DispatchQueue.global` both hang indefinitely,
  confirmed against the real app binary — see P2-009). Every engine call
  must run synchronously on `MainActor` until P2-009 is root-caused.
  This supersedes any earlier assumption that `Task.detached` was a safe
  way to keep the UI responsive during a slice.
- **Camera orbits around world Z as vertical, not Y** — matches every
  mesh/toolpath/plate vertex's real convention (bed Z=0, G-code Z is
  print height). Any future camera/raycast work must preserve this;
  `screenPointToRay` already derives everything from `Camera`'s own
  matrices, so it needed no separate fix.

## Uncommitted changes
None once this commit lands — Phase 7 is complete for everything
verifiable without hardware. Full suite currently passes 179/179.

## Known blockers
- **MakerWorld actual auth/browse/download:** public API does not exist;
  reverse-engineering bind-ticket endpoints remains out of scope.
- **MyMiniFactory live OAuth/download:** requires user-supplied registered
  OAuth credentials and P8-006's packaged/Launch-Services-registered app.
  This environment's Cloudflare challenge prevents live API proof.
- **FTPS/MQTT/camera live hardware proof:** `FTPSUploaderIntegrationTests`/
  `CameraStreamClientIntegrationTests` prove the real protocols against
  real local TLS servers; no physical A1 is available to prove them
  against actual printer firmware.
- **P6-007 OrcaSlicer benchmark:** no OrcaSlicer binary installed/vendored
  here; building it from source is out of proportion to one benchmark.
- **P6-008/P2-008 hardware validation:** no physical A1/AMS Lite is
  available.
- **P2-009:** background-thread engine calls hang; root cause
  undiagnosed. Currently mitigated by running synchronously on MainActor
  (UI freezes during slice/calibrate/optimization-details, does not
  hang).
- P3-004 multicolor painting remains deferred; P4-002 needs an observed
  non-manifold repair case.
- Device workflow "start a new print" and P7-007's G-code-load both need
  a project-3MF-with-embedded-G-code writer (BambuStudio's `Format/
  bbs_3mf.cpp` equivalent) this codebase has never ported — real upload/
  pause/resume/stop and loading an existing `.gcode` for Preview both
  work today; writing one back out as a `.3mf` does not yet.

## Next recommended action
1. Investigate P2-009 (background-thread engine hang) if slicing
   performance/UI-freeze becomes a real user complaint — not urgent now
   that it's a freeze instead of a hang, but worth root-causing before
   P8 production packaging.
2. Implement a project-3MF-with-embedded-G-code writer if "start a new
   print from this app" or "save a loaded G-code as a project" becomes a
   priority.
3. Begin Phase 8 (production packaging) — P8-006 in particular would
   unblock live OAuth/FTPS/camera/MakerWorld verification currently
   blocked purely on packaging, not on missing implementation.

## Relevant commands
- `swift build` / `swift test` / `swift run NativeSlicerA1`
- `swift test --filter BuildPlateGeometryTests` — 4 real plate/grid/axis tests
- `swift test --filter ProjectDocumentExportArrangeTests` — export/arrange + the slice-hang regression test
- `swift test --filter FTPSUploaderIntegrationTests` — real local TLS FTP upload
- `swift test --filter CameraStreamClientIntegrationTests` — real local TLS camera-frame fetch
- `swift test --filter GCodeLoadTests` — real round-trip of a loaded .gcode file
- `swift test --filter MakerWorldLinksTests` — 4 real domain-trust tests
- `swift test --filter ModifierVolumeTests` — 2 real modifier-mesh tests
- `swift test --filter PlatePreviewTests` — 3 real plate-preview tests
- `swift test --filter MultiPlateTests` — 5 real multi-plate tests
- `swift test --filter CutModelTests` — 7 real cut/connector-boolean tests
- `swift test --filter ProjectDocumentCutTests` — 10 real cut/connector/modifier/undo tests
- `swift test --filter CutGroupIDPersistenceTests` — 2 real cut_id/3MF tests
- `swift test --filter ConnectorTests` — 6 real connector-mesh tests
- `swift test --filter VariableLayerHeightTests` — 2 real layer-height-range tests
- `swift test --filter SupportPaintingTests` — 5 real paint engine tests
- `swift test --filter RaycastTests` — viewport hit testing + ray-plane
- `swift test --filter AutoArrangeTests` — 3 orient/arrange tests
- `cd vendor/BambuStudio/build/arm64 && ninja libslic3r libnest2d` — only
  for temporary upstream instrumentation; ALWAYS revert vendor sources
  afterward (`git -C vendor/BambuStudio checkout --`).
- When touching an existing hot-path C-ABI function's signature: run the
  FULL suite 3-5× before trusting a clean result, or add a sibling
  function instead — see the toolchain-sensitivity finding above.
- Manual GUI smoke test: launch via a real `.app` bundle (the raw
  `.build/out/Products/Debug/NativeSlicerA1` executable run directly is
  NOT Dock-registered and exits when its launching terminal session
  ends) — wrap it: `mkdir -p /tmp/NativeSlicerA1.app/Contents/MacOS`,
  write a minimal `Info.plist`, symlink the built executable in, then
  `open -n /tmp/NativeSlicerA1.app`.
- Screenshot verification in THIS environment: resolve the window's
  `CGWindowID` and use `screencapture -l<id> -o -x`, not plain
  `screencapture -x` (see "desktop focus contention" finding above).
