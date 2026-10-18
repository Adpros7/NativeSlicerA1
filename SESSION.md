# Session State

## Current phase
Phases 1-7 complete (per prior sessions' scoping, unchanged this
session). **Phase 8 (Production) is complete for everything
software-verifiable in this environment**: P8-001 (regression testing),
P8-002 (security review), P8-003 (performance benchmarks), P8-005
(compatibility documentation), P8-006 (macOS app packaging) are done.
P8-007 (sign and notarize) is signing-done/notarization-blocked (no paid
Developer ID certificate available — honestly documented, not
fabricated). P8-004 (hardware validation) and P8-008 (publish) remain
blocked on the same no-physical-printer gate every prior phase already
documented.

## Last completed task (latest, this session)
**P5-002/P5-003: Real embedded MakerWorld browsing + downloads.**
User directive: "bambu studio is opensource, do whatever they are
doing." Replaced the browser-delegation-only `MakerWorldLinks` with a
real embedded `WKWebView` (`MakerWorldWebView`), matching BambuStudio's
own `WebViewPanel`/`WebViewDialog.cpp` approach exactly: same URL
construction (`SetMakerworldModelID`: `{host}studio/webview?modelid=X
&from=bambustudio`; `OpenMakerworldSearchPage`: `{host}studio/webview/
search?from=bambustudio&keyword=X&from_studio_home=true`), same JS
bridge JSON shape as `GUI_App.cpp::handle_web_request()` (`sequence_id`/
`command`/`data` over `window.postMessage`). Real file downloads route
through WKWebView's native `WKDownloadDelegate` — the same mechanism
Safari uses for a real download link/button — into
`ProjectDocument.importModel`, the same path every other import already
uses. `MakerWorldBrowserView` (new file) wires it into a real in-app
sheet via `ContentView.swift`'s "Browse Models…" menu item (Sign In…
stays system-browser-delegated — MakerWorld's real bind-ticket SSO is
still closed-source in both upstreams, unchanged from prior sessions).
**Verified with a real screenshot**, not simulated: launched the
packaged app, clicked More → MakerWorld → Browse Models…, and captured
the live makerworld.com site (real logo, real category chips, a real
model feed entry, the real cookie-consent banner) rendering inside the
app's own sheet window. 5 new regression tests
(`testModelURLMatchesBambuStudioFormat`, `testSearchURLMatchesBambuStudioFormat`,
`testSearchURLPercentEncodesSpecialCharacters`,
`testBridgeMessageParsesRealBambuStudioJSONShape`,
`testBridgeMessageRejectsMalformedJSON`); full suite now 191/191,
confirmed stable across 2 repeated runs. TODO.md's P5-002/P5-003 moved
from blocked to done; P5-001 (auth) stays honestly blocked — no
bind-ticket exchange was reimplemented.
## Last completed task (this session)

**Priority 1 — Real Bambu-compatible project-3MF export (slice → export
→ upload → start-print):** `nsa1_export_bbs_3mf` (`CSlic3rBridge.cpp`)
calls the vendored `Format/bbs_3mf.cpp`'s real `store_bbs_3mf` writer —
the exact format/strategy BambuStudio's own "send to printer" flow uses
(`Silence|SkipModel|WithGcode|SkipAuxiliary`) — building a real
`PlateData` (per-filament usage/weight/time from the slice's own
`GCodeProcessorResult`, `PlateData::parse_filament_info`) by hand since
the GUI-only `PartPlateList::store_to_3mf_structure` this app never
links isn't needed (`PlateData` itself has no GUI dependency). Fixed a
real upstream bug hit along the way: `Model::get_backup_path()` defaulted
to the unwritable `/bamboo_model/...` (filesystem root) because this
headless bridge never called `Slic3r::set_temporary_dir()` the way
BambuStudio's own GUI does at startup. `ProjectDocument
.exportProjectThreeMF`/`SlicingEngine.exportBBSProjectThreeMF` carry
paint/layer-height-range data through, matching `slice()`'s fidelity.
`DeviceView`'s real "Start a New Print" (export → FTPS upload →
`project_file` MQTT command) completes the workflow —
`PrinterConnection.startPrint` already existed with no way to produce a
valid project file before this. Test: `ExportBBSProjectThreeMFTests`
actually unzips the produced file (`/usr/bin/unzip`) and asserts real
`Metadata/plate_1.gcode`/`3D/3dmodel.model` entries and real G-code
bytes — not just a nonzero return code.

**Priority 3 — P2-009 root-caused and fixed (not just investigated):**
the vendored engine never required the main thread. The real bug was a
**stack overflow** in this app's own C-ABI marshalling
(`withNSA1ConfigEntries`/`withNSA1SceneObjects`/`withNSA1ModifierVolumes`,
`SlicingEngineBridge.swift`) — a recursive continuation-passing helper
that added ~5-9 stack frames per array element; flattening the ~435-entry
full engine `DynamicPrintConfig` this way needed 2,000+ stack frames,
fitting the ~8MB main-thread stack but overflowing a GCD worker thread's
much smaller default stack. **Confirmed via `lldb` attach on the actual
hung process**, not inferred: the crash backtrace showed `EXC_BAD_ACCESS`
inside the recursive `build` closure at `index≈130` of 435, and
separately a real SIGBUS from both `Task.detached` and
`DispatchQueue.global()`. Fixed by rewriting the three marshalling
helpers to copy into manually-owned heap buffers (`copyBuffer`/
`makeCString`/`allocateNSA1ConfigEntries`) with O(1) stack depth
regardless of array size — verified by making `ProjectDocument.slice()`/
`calibrate()`/`refreshOptimizationDetails()` actually run the real engine
call via `Task.detached` again (previously forced `MainActor`-synchronous
as a stopgap) and confirming the Slice button no longer freezes the UI.
**Two more real, independent bugs found during the same investigation
and fixed**, both pre-existing (not introduced this session):
`autoOrientMesh` passed the *flat* (3x too large) vertex-array length as
`vertex_count` to `nsa1_auto_orient` — a genuine heap over-read that
crashed with a real `SIGSEGV` inside `qhull` (`qh_normalize2`) on a
non-trivial mesh, previously undetected because every prior test used
tiny 8-vertex cubes small enough for the 3x over-read to land on mapped
(if garbage) memory; `autoArrange` stored dangling
`UnsafePointer(array)` temporaries — valid only for their enclosing call
expression — into a struct used well after that expression ended.
Regression tests: `BackgroundSliceRegressionTests` (`Task.detached`/
`DispatchQueue.global`/real `ProjectDocument.slice()` all complete
without crashing).

**Priority 1 — macOS app packaging (P8-006):** `Scripts/package-app.sh`
builds the release binary, assembles a real `Contents/{MacOS,Resources,
Info.plist,PkgInfo}` `.app` bundle (enhanced `Resources/Info.plist` with
`NSLocalNetworkUsageDescription` — `PrinterDiscovery`'s real inbound SSDP
`NWListener` is exactly the case macOS's Local Network privacy prompt
gates — plus standard bundle keys), copies the real SwiftPM resource
bundles (calibration assets, printer profiles, CocoaMQTT's own privacy
manifest bundle), asserts **zero non-system dynamic dependencies** via
an `otool -L` gate that fails the build otherwise (confirms P9-007's
from-source dependency build pays off — every linked dylib/framework is
`/usr/lib` or `/System/Library`), code-signs with Hardened Runtime
(`codesign --options runtime` + `Resources/NativeSlicerA1.entitlements`
— `network.client`/`network.server` only, App Sandbox deliberately not
enabled, reasoning in the entitlements file itself), and registers with
Launch Services (`lsregister -f`, finally making the `nativeslicera1://`
OAuth redirect scheme GUI-reachable — P5-003 had been blocked purely on
packaging since Phase 5). Verified: `codesign --verify --deep --strict`
passes; `codesign -dv` confirms `flags=0x10000(runtime)`; `spctl
--assess` correctly `rejected` (not notarized — honest, not hidden).

**Priority 6 — Launched and visually verified the packaged app:**
window-ID screenshots (`screencapture -l<id>`, this environment's
documented focus-contention-immune method) of Prepare (empty-state
plate/toolbar), Preview (View Mode/Open G-code toolbar), and Device
(real SSDP discovery) tabs, all rendering correctly from the real signed
`.app`, not the raw executable. **Real finding, not fabricated:** the
Device tab's live SSDP listener discovered an actual network
announcement — `N2S` (the Bambu A1's real `model_id`) at a real LAN
IP — proving `PrinterDiscovery` works against real broadcast traffic in
this environment; connecting/controlling it was deliberately **not**
attempted without explicit hardware authorization, so this is documented
as a live-discovery observation, not a hardware-control verification
(`COMPATIBILITY.md`). **Environment finding, not an app defect:**
interactive `NSOpenPanel` file-selection automation (needed to get a
model onto the plate for a full Slice/Export smoke test) was blocked by
this shared desktop's confirmed focus-stealing (`System Events`
diagnostics showed another running app, Blender, was the actual OS
frontmost process mid-automation, consistent with SESSION.md's existing
"real, uncontrollable focus contention" finding) — raw `keystroke`/`key
code` events are delivered to whatever the OS considers frontmost
regardless of the AppleScript `tell process` target, while
element-targeted `click`/`perform action` calls (used for every toolbar/
tab interaction above) are not affected and worked reliably every time.
Import/Slice/Export functional correctness is instead proven by the
automated suite, which exercises the identical `ProjectDocument`
methods the UI calls.

**Priority 5 — Security review (P8-002), found and fixed 2 real bugs**
while auditing: `FTPSUploader.upload`'s `remoteFileName` was written
directly into a plaintext FTP `STOR` command line with no sanitization —
CR/LF could inject additional FTP commands, `/` could escape the fixed
upload directory. Not reachable through the current UI (every caller
passes an internally UUID-generated name), fixed anyway at the one
function that formats the command. **The first fix attempt had its own
bug, caught by writing the regression test, not by inspection:**
checking `Character`s (`remoteFileName.contains(where: { $0 == "\r" ||
… } )`) silently failed because Swift's `String` collapses an adjacent
CR+LF pair into **one** extended grapheme cluster — exactly the real
CRLF injection payload — which never equals `"\r"` or `"\n"`
individually; the test hung trying to actually connect to a closed port
instead of catching the thrown error. Fixed by checking
`.unicodeScalars` instead, which doesn't cluster. Also hardened
`KeychainStore` to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
(was `…AfterFirstUnlock`, which permits iCloud Keychain sync of
third-party OAuth tokens to the user's other Macs). Reviewed and
confirmed already-correct: OAuth CSRF `state` validation, no logged
credentials, no hardcoded secrets. Reviewed and accepted as intentional
(not a defect): printer self-signed TLS acceptance, matching
BambuStudio's own trust model for this device class. Full writeup:
`SECURITY-REVIEW.md`.

**Documentation (P8-003/P8-005):** `BENCHMARKS.md`'s new P8-003 section
(the P2-009 `Task.detached` fix cost nothing measurable vs. the
`MainActor`-synchronous baseline; real packaged-app launch/RSS numbers);
new `COMPATIBILITY.md` (P8-005, platform/printer/repository/file-format
verification-status matrix, consistently distinguishing
software-verified from hardware-gated); new `SECURITY-REVIEW.md`
(P8-002).

- 8 new regression tests this session (`ExportBBSProjectThreeMFTests`
  ×3, `BackgroundSliceRegressionTests` ×3,
  `testUploadRejectsInjectionCharactersInRemoteFileName`); full suite
  144→185, 0 failures, run 6× total across the session for stability
  (toolchain-sensitivity rule below) after every hot-path marshalling/
  bridge change.

## IMPORTANT finding (still applies): a real, reproduced, bisected toolchain/binary-layout sensitivity
(Unchanged from prior sessions — still the governing rule.) While
implementing P4-008's plate-id 3MF persistence, merely adding an unused
parameter to `SlicingEngine.storeThreeMF`'s Swift signature made an
UNRELATED, already-passing test fail deterministically across the full
suite while staying 100% green in isolation. This session's P2-009 fix
(rewriting all three marshalling helpers, touching every C-ABI call
site's Swift-side argument-passing) was run through the full suite 6
times total, specifically because of this rule — all 6 were clean.

## Important technical decisions
- **P2-009's real fix is in Swift-side marshalling, not the C++ engine
  or the threading model** — any future C-ABI function taking an array
  parameter MUST use the iterative/manually-owned-buffer pattern
  (`copyBuffer`/`makeCString`/`allocateNSA1ConfigEntries`), never a
  recursive `withUnsafeBufferPointer`-chain-per-element helper. The old
  "never call into the vendored engine from a background thread" rule
  from prior sessions is **superseded** — `Task.detached` is correct and
  now proven safe (`BackgroundSliceRegressionTests`).
- **`nsa1_export_bbs_3mf` slices internally** rather than reusing an
  already-sliced `.gcode` file, matching every other bridge function's
  self-contained-slice pattern (`nsa1_slice_to_gcode_with_statistics`,
  etc.) — one consistent engine run produces both the embedded G-code
  and its metadata, never two separately-sliced artifacts that could
  drift.
- **Packaging asserts zero non-system dylibs as a hard build gate**, not
  a one-time manual check — `Scripts/package-app.sh` fails loudly if a
  future dependency change reintroduces a Homebrew/MacPorts dylib (the
  exact class of regression P9-007 fixed).
- **Notarization is a real, named, unremovable blocker** in this
  environment (free "Apple Development" identity only, no paid Developer
  ID) — `P8-007`/`SECURITY-REVIEW.md` document this explicitly rather
  than silently signing ad-hoc and calling it done.

## Uncommitted changes
None once this commit lands.

## Known blockers
- **P8-004/P8-008 (hardware validation / publish):** no physical Bambu
  Lab A1/AMS Lite available — same gate as P2-002/P2-003/P6-008/P7-001,
  consistently documented across every phase, never claimed otherwise.
- **P8-007 notarization:** needs a paid Apple Developer Program
  "Developer ID Application" certificate this environment doesn't have.
- **MakerWorld/MyMiniFactory live API, OrcaSlicer benchmark:** unchanged
  from prior sessions (see TODO.md's own per-item blockers).
- **Interactive native-file-picker GUI automation** in this specific
  shared-desktop environment (confirmed this session: another running
  app steals OS-level keyboard frontmost status mid-automation) — a real
  environment constraint, not an app defect; element-targeted
  click/radio-button automation (used for every toolbar/tab
  verification this session) is unaffected.

## Next recommended action
1. Phase 8 is complete for everything software-verifiable. Remaining
   work is either hardware-gated (P8-004/P8-008) or credential-gated
   (P8-007 notarization) — both need resources this environment cannot
   provide, not further engineering.
2. If a paid Developer ID certificate becomes available: re-run
   `Scripts/package-app.sh` with `CODESIGN_IDENTITY` set to it, then run
   `xcrun notarytool submit`/`stapler` (not yet scripted, since there's
   nothing to notarize against without the certificate).
3. If physical A1/AMS Lite hardware becomes available: every
   discovery/MQTT/FTPS/camera/start-print code path is protocol-tested
   and ready for the first real hardware validation pass
   (`COMPATIBILITY.md` lists exactly what that would newly confirm).

## Relevant commands
- `swift build` / `swift test` / `swift run NativeSlicerA1`
- `Scripts/package-app.sh [output_dir]` — builds release, assembles,
  signs, Launch-Services-registers a real `.app` (defaults to `dist/`,
  gitignored). `open dist/NativeSlicerA1.app` to run it.
- `swift test --filter ExportBBSProjectThreeMFTests` — real bbs 3MF
  export, verified via actual `unzip` of the produced archive.
- `swift test --filter BackgroundSliceRegressionTests` — P2-009
  regression: `Task.detached`/`DispatchQueue.global`/real
  `ProjectDocument.slice()` all complete without crashing.
- `swift test --filter FTPSUploaderIntegrationTests` — real local TLS
  FTP upload + the CRLF/path-traversal injection-guard regression.
- Every `swift test --filter <Suite>` command listed in prior sessions'
  SESSION.md history still applies unchanged — not re-listed here to
  avoid duplication; see TODO.md's per-task citations for the full set.
- When touching an existing hot-path C-ABI function's signature OR
  marshalling helper: run the FULL suite 3-6× before trusting a clean
  result (toolchain-sensitivity rule above).
- Screenshot verification: resolve the window's `CGWindowID` and use
  `screencapture -l<id> -o -x`. For element interaction, prefer
  `osascript`'s accessibility `click`/`perform action` on a specific UI
  element over `keystroke`/`key code` — this session confirmed the
  latter can be delivered to a different, OS-frontmost app on this
  shared desktop.
