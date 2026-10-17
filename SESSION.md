# Session State

## Current phase
Phase 1 (Application Foundation) and Phase 2's non-hardware items complete.
Phase 3: P3-001 audit, P3-002 calibration, and P3-005 support painting
complete. **Phase 4 (Geometry) is fully complete** except P4-002
(intentionally deferred pending an observed real need). Phase 5 (Online
Models): P5-001/P5-002 complete (scoped to what's actually safe/real);
P5-003/004/005 are genuinely blocked (documented in TODO.md, not
silently skipped — see below). Phase 9 P9-007 is complete.

## Last completed task
P5-001/P5-002: MakerWorld integration, scoped after an explicit user
design decision (asked via the `ask` tool, since TODO.md itself flags a
real licensing/ToS risk and says to resolve this before implementation):
delegate entirely to the system browser via `ASWebAuthenticationSession`.

Investigation first (RESEARCH-P0-011-CONNECTIVITY.md, already in the
repo): MakerWorld's real SSO mechanism (`func_request_bind_ticket`,
`NetworkAgent.cpp`) is closed-source in BOTH BambuStudio and OrcaSlicer —
it wraps a proprietary `bambu_networking` plugin binary with zero public
API documentation. There is nothing to reimplement; reverse-engineering
Bambu's internal endpoints would itself be the ToS risk the research doc
warns about. So P5-001/P5-002 are scoped to exactly what's real and safe:

- `MakerWorldLinks.swift`: a domain-trust whitelist (`isTrusted`) gating
  every URL this app will ever hand to the system — real domains only
  (`makerworld.com`, `makerworld.com.cn` — both cited as exact literals
  from `.research/BambuStudio/src/slic3r/GUI/GUI_App.cpp:1608,1611,1639`
  — plus the two real CDN domains from RESEARCH-P0-011-CONNECTIVITY.md
  §3.2). Rejects lookalikes (`evil-makerworld.com`,
  `makerworld.com.evil.example`) and non-HTTPS. `openInSystemBrowser` is
  the single chokepoint every MakerWorld URL goes through — refuses an
  untrusted URL rather than silently opening it.
- `MakerWorldAuthPresenter`: wraps `ASWebAuthenticationSession` to open
  the real `makerworld.com` login in a system auth sheet. Honestly
  documented limitation: MakerWorld has no documented OAuth redirect
  scheme for third-party apps, so this app cannot detect "signed in" as
  a completion callback the way a real OAuth flow would — the user logs
  in with their real Bambu account directly on Bambu's own domain (this
  app never sees credentials) and dismisses the sheet manually.
  `prefersEphemeralWebBrowserSession = false` so the session persists in
  the shared system browser session, same as a normal login.
- ContentView: a "MakerWorld" menu with "Sign In…" and "Browse Models…".

`Tests/NativeSlicerA1Tests/MakerWorldLinksTests.swift`: 4 tests — real
domains trusted, lookalike/non-HTTPS domains rejected, the app's own
sign-in/browse URLs pass their own trust check, `openInSystemBrowser`
refuses an untrusted URL. Full suite: 129 tests passing (no C++ changes
this task — pure Swift addition, no toolchain-sensitivity risk).

P5-003 (model downloading)/P5-004 (direct slicing workflow)/P5-005
(additional repos) are documented in TODO.md as **genuinely blocked**,
not silently skipped: MakerWorld's real "open in slicer" flow
(`makerworld_model_open` JS command) only exists inside BambuStudio's
embedded webview, which this app deliberately doesn't build (the P5-001
licensing decision). With no public download API and no embedded
webview, there's no remaining integration surface — a user who downloads
a `.3mf` from MakerWorld in their browser already gets full value from
this app's existing Import (P1-004/P1-005) and the complete real
slicing/cut/connector/modifier pipeline, with zero new code needed.

Before that (same session): P4-013 modifier meshes completed Phase 4
(Geometry) in full except the intentionally-deferred P4-002. Pushed
`eea7709`.

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
(Not relevant to this session's P5 work — pure Swift, no C++ touched.)

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
  (BambuStudio's separate full project format, not used here).

## Uncommitted changes
P5-001/P5-002 (MakerWorld browser delegation) is implemented and fully
tested (129/129) but not yet committed/pushed as of this update.

## Known blockers
P5-003/004/005: genuinely blocked by the same closed-source MakerWorld
API constraint (documented in TODO.md, see above) — not a technical gap
to close, revisit only if MakerWorld publishes a public API. P3-004
(multicolor painting) stays deferred per explicit TODO.md P4/lowest-
priority note. P4-002 manual repair remains conditional on observing a
real mesh-repair need.

## Next recommended action
1. Commit + push P5-001/P5-002 (see Uncommitted changes above).
2. Phase 4 (Geometry) and the real portion of Phase 5 (Online Models)
   are now both complete. Natural next steps, in priority order:
   - Phase 6 (Optimization): P6-001 benchmarks, P6-002..006 (color-
     transition/purge/region/collision optimization, reports) — pure
     software work building directly on the now-complete real engine
     integration, no legal/hardware ambiguity.
   - Phase 7 (Intelligent Features): P7-001 camera access, P7-002..004
     (failure detection, monitoring, intervention) — per
     RESEARCH-P0-011-CONNECTIVITY.md §2.2/2.4, camera needs a
     reverse-engineered proprietary port-6000 protocol (1 fps, A1-
     specific) and failure detection needs real MQTT report field
     parsing (`PrinterConnection.swift` transport already exists,
     structured parsing doesn't) — needs real/simulated printer access
     to verify meaningfully, unlike Phase 6's pure-software work.
   - The connectivity research doc (RESEARCH-P0-011-CONNECTIVITY.md)
     also flags real, concrete gaps worth independent pickup regardless
     of phase: FTPS print upload (P1, ≤250KB A1 limit documented), print
     control convenience methods (pause/resume/stop/start wrappers over
     the existing generic `send()`), and structured MQTT status-report
     parsing + monitoring UI — none require the MakerWorld ToS
     boundary and all have concrete acceptance criteria already written.
3. A real gap noticed in a prior session but NOT yet fixed: `ProjectDocument.
   slice()` iterates ALL `objects`, not `objectsOnActivePlate` — P4-008
   added per-plate grouping but the main slice path never respects it.
4. Minor pre-existing cleanup: `SlicingEngine.autoArrange`'s
   `UnsafePointer(meshData.vertices)`/`UnsafePointer(meshData.indices)`
   construction triggers the same dangling-temporary-pointer warning
   fixed in `cutModel` — not yet reproduced as a failure, worth an
   eventual fix using `withNSA1SceneObjects`.

## Relevant commands
- `swift build` / `swift test` / `swift run NativeSlicerA1`
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
