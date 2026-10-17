# Session State

## Current phase
Phase 1 and Phase 4 (except conditional P4-002 repair) are complete. Phase
5 is **not complete**: MakerWorld has only an intentionally safe
trusted-browser handoff, not actual authentication, browsing, or downloads.
Phase 6 investigation is complete and implementation is next. Phase 2's
remaining software connectivity gaps (upload/status/control) and Phase 7
remain pending.

## Last completed task
Phase 5 audit and a documented alternative-repository integration are
implemented but not yet committed:

- The former P5-001/P5-002 completion claim was corrected. Opening
  `makerworld.com` with `ASWebAuthenticationSession` delegates to an
  external site; NativeSlicerA1 cannot observe login, query models, render
  results, receive a selected model, or download it. `TODO.md` and
  `FEATURE_PARITY.md` now leave actual MakerWorld auth/browse/download open
  and record the closed-source bind-ticket blocker precisely.
- `RESEARCH-P5-MODEL-REPOSITORIES.md` evaluates public alternatives:
  Thingiverse and MyMiniFactory both presented Cloudflare challenges from
  this environment (no bypass attempted); Printables has no documented
  public API; Cults3D's documented GraphQL API excludes download files.
  MyMiniFactory is selected because its official OpenAPI spec + OAuth
  instructions explicitly document search, file metadata, and the
  OAuth-only download URLs.
- `MyMiniFactoryClient.swift`, `MyMiniFactoryAuth.swift`, and
  `MyMiniFactoryView.swift` implement a genuine in-app MyMiniFactory
  integration: API-key catalog search, OAuth authorization-code exchange,
  Keychain-only credential/token storage, OAuth bearer download, and direct
  STL/3MF import through the existing `ProjectDocument.importModel` path.
  It is not an external-browser workaround.
- `Resources/Info.plist` declares the OAuth callback scheme and is embedded
  in the executable's `__TEXT,__info_plist` section. `plutil -lint` and
  `otool -l` verified the embedded section. OS callback routing still
  requires P8-006's packaged, Launch-Services-registered `.app`, so
  end-to-end OAuth and live API verification remain honest blockers.
- New regression coverage: 5 real Keychain round-trip/delete tests and 9
  mock-transport API/OAuth/download tests. `swift test`: 143 tests passed.
  A temporary `.app` with the production plist launched successfully and a
  captured macOS screenshot confirms the native app surface.

Phase 6 source investigation (`agent://VisitingNarwhal`, summarized below)
established that all required optimization primitives already exist in the
vendored engine. Reuse them through new sibling C-ABI functions; never
reimplement tool ordering, purge calculations, or collision geometry in
Swift.

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
Phase 5 audit + MyMiniFactory integration, documentation, Info.plist
embedding, and 14 new regression tests. Full suite currently passes
143/143. Commit after a focused diff review.

## Known blockers
- **MakerWorld actual auth/browse/download:** public API does not exist;
  reverse-engineering bind-ticket endpoints remains out of scope.
- **MyMiniFactory live OAuth/download:** requires user-supplied registered
  OAuth credentials and P8-006's packaged/Launch-Services-registered app.
  This environment's Cloudflare challenge prevents live API proof.
- **P6-008 hardware validation:** no physical A1/AMS Lite is available.
- P3-004 multicolor painting remains deferred; P4-002 needs an observed
  non-manifold repair case.

## Next recommended action
1. Commit/push the Phase 5 audit/integration milestone.
2. Execute Phase 6 using existing upstream data: `GCodeProcessorResult`
   contains tool/color IDs and flush statistics; `Print::tool_ordering()`
   supplies per-layer order; `Print::validate()` has actual collision
   checks and visualization polygons. Add **sibling** bridge APIs only,
   then benchmark before/after and expose a report.
3. After Phase 6, implement software-verifiable FTPS/MQTT/control gaps,
   then audit/implement feasible Phase 7 tasks.

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
