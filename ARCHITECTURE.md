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

## P1-008: Conventional slicing bridge (real G-code via `Print::apply`/`process`/`export_gcode`)

Extends the C-ABI bridge (not a new interop mechanism) with
`nsa1_slice_to_gcode`: builds a `Slic3r::Model` from placed scene objects
(same `TriangleMesh`/`ModelInstance` pattern as `nsa1_store_3mf`), seeds a
`Slic3r::DynamicPrintConfig` from `DynamicPrintConfig::full_print_config()`,
overlays the resolved Bambu A1 profile fields (`BambuProfileLoader`'s
already-tested `inherits`-chain resolution, serialized to libslic3r's own
comma-joined array format), then drives the engine's real
`Print::apply(model, config)` → `validate()` → `process()` →
`export_gcode(path)` pipeline — no reimplemented slicing logic.

**Upstream bug found and worked around:** `DynamicPrintConfig::full_print_config()`
clones each `ConfigOptionDef`'s raw `default_value` directly. For
`coEnum`/`coEnums` options, that raw default value's `keys_map` pointer is
never wired up (only `ConfigOptionDef::create_default_option()` — used by
`set_deserialize()`'s "key not yet present" path — does that). Any enum
option already seeded by `full_print_config()` therefore carries a null
`keys_map` and null-derefs the instant anything calls `deserialize()` or
`serialize()` on it (overriding it from a profile, or the engine itself
embedding it in the G-code header's `; CONFIG_BLOCK` later — reproduced
and diagnosed via `lldb` backtraces into
`ConfigOptionEnumsGenericTempl<NULLABLE>::deserialize`/`serialize_single_value`).
Worked around in `nsa1_slice_to_gcode` with a repair pass right after
seeding: walk every currently-present option, and for any `coEnum`/
`coEnums` option whose instance `keys_map` is null, copy it from the
(correctly populated) `ConfigOptionDef::enum_keys_map`. Covers both the
non-nullable (`ConfigOptionEnumsGeneric`) and nullable
(`ConfigOptionEnumsGenericNullable`) variants.

**No better upstream fix exists for our use case:** `full_print_config()`
has exactly one other real caller in the vendored tree, `Calib.cpp:693`
(`DynamicPrintConfig full_defaults = DynamicPrintConfig::full_print_config();
full_defaults.apply(m_config, true);`) — it never calls
`deserialize()`/`serialize()` on the raw broken defaults directly; it
immediately `.apply()`s an already-correctly-keyed config over it, which
copies option values without touching `keys_map`. `nsa1_slice_to_gcode`
can't use that pattern: it needs `set_deserialize()` to parse the A1
profile's config strings (`BambuProfileLoader`'s resolved
string-typed fields) into typed options, which is exactly the path that
needs `keys_map`. The targeted repair pass is the minimal fix.

**Verified as a genuine regression, not a theoretical one:** temporarily
removing the repair pass and rebuilding reproduces a real SIGSEGV
(signal 11) on `SlicingJobTests.testEnumProfileOptionsSurviveRepairedKeysMap`
(and `testSlicesCubeIntoRealGCode`) — confirmed by running the test suite
against the unpatched binary, not inferred. That test (added alongside
this verification) asserts on two real A1-profile-set enum options
surviving into the actual G-code header: `gcode_flavor` (scalar `coEnum`,
`fdm_machine_common.json`) and `overhang_fan_threshold` (per-extruder
array `coEnums`, `fdm_filament_pla.json`) — covering both repaired option
variants, not just "no crash".

**Known gap, now resolved:** the per-nozzle-variant `"include"` key
(custom start/end/layer-change G-code template references, e.g. `Bambu
Lab A1 0.4 nozzle template machine_start_gcode.json`) is now resolved by
`BambuProfileLoader.resolve`, mirroring `PresetBundle.cpp`'s
`load_system_models`/`load_system_filaments` three-tier precedence
(`config = *default_config` → each `include` profile's own fields applied
in list order → the profile's own fields win last). Each vendored
`*template*gcode*.json` has no `inherits` of its own and exactly one real
field besides `name`/`instantiation`, so merging its fields directly is
equivalent to upstream's `include_config.diff(include_default_config)`
restriction without needing the full default-preset closure here.
Verified by `BambuProfileLoaderTests.testResolvesIncludedGCodeTemplates`
(resolved `machine_start_gcode` contains the A1-specific `M9833.2` marker
absent from the generic `fdm_machine_common` ancestor) and
`SlicingJobTests.testIncludedA1StartGCodeReachesRealOutput` (the marker
reaches the real sliced G-code file, not just the resolved config dict).

Verified by `SlicingJobTests.testSlicesCubeIntoRealGCode`: a real 20mm
cube mesh, sliced through the real engine with the real vendored A1
machine/process/filament profile closure, produces a real multi-layer
(100 layers at 0.2mm) G-code file with the real BambuStudio-format header
(`; BambuStudio 02.08.04.61`, `; nozzle_diameter = 0.4`, printer
identification) — manually inspected, not just asserted in-test.

## P1-009: G-code visualization (real toolpath from the engine's own `GCodeProcessorResult`)

`Print::export_gcode` already computes a full per-move toolpath
(`GCodeProcessorResult::moves`, used internally by BambuStudio's own
G-code preview) — P1-008's bridge call was discarding it. P1-009 exposes
it instead of recomputing anything: `nsa1_slice_to_gcode` gained an
optional `NSA1Toolpath **out_toolpath` parameter. For each consecutive
pair of `Extrude`/`Travel` moves it emits one `NSA1ToolpathSegment`
(start/end position, width, height, travel flag); non-move events
(retract, seam, tool change, …) break the polyline so segments never
bridge unrelated moves.

Swift side: `SlicingEngine.sliceToGCode`/`SlicingJob.slice` now return
`[ToolpathSegment]`. `MetalRenderer.setToolpath` uploads it as a single
GPU line-list buffer (interleaved position+color, extrude orange / travel
gray) and draws it with a dedicated compiled line pipeline
(`toolpath_vertex`/`toolpath_fragment` in `Shaders.swift`) alongside the
existing mesh pipeline — no mesh preview code was touched.

`ProjectDocument.slice()` runs the (potentially slow) real pipeline via
`Task.detached` off the `@MainActor`, so the UI stays responsive;
`isSlicing` drives the toolbar button's disabled/label state. A fresh
`BambuProfileLoader()` is constructed per slice rather than cached on the
document — cheap (reads vendored JSON once per call) and avoids any
actor-isolation complexity for a loader with no mutable state.

Verified by `MetalRendererTests.testDrawEncodesRealToolpathFromRealSlice`:
a real cube, sliced through the full P1-008 pipeline, yields a real
multi-hundred-segment toolpath (with real extrusion segments present,
not just travel) that uploads and draws without crashing against the
compiled GPU pipeline.



## P0-006: Metal rendering architecture

Standard MetalKit integration, no third-party rendering engine:
- `MTKView` wrapped by `MetalViewport` (`NSViewRepresentable`) for SwiftUI embedding.
- `MetalRenderer: NSObject, MTKViewDelegate` owns the device, command queue, runtime-compiled MSL pipeline, depth state, orbit camera, and mesh GPU-buffer cache.
- Imported `LoadedMesh` triangle data is uploaded to indexed Metal vertex/index buffers exactly once per source mesh; per-frame work is only an object transform/color uniform and indexed draw call.
- Geometry uses flat derivative normals in the fragment shader, avoiding a redundant CPU normal buffer; selection changes object color.
- `OrbitMTKView` handles mouse-drag orbit and scroll-wheel zoom directly. No gesture/camera dependency.
- `ProjectDocument` owns immutable source meshes and mutable `SceneObject` placements. Import/open/save UI binds it to the viewport. Project persistence uses `libslic3r`'s own `.3mf` reader/writer (`load_3mf`/`store_3mf`), not an invented JSON side format.

## P0-012: Application architecture (finalized)

```mermaid
graph TD
  UI[SwiftUI Views] --> VM[Observable App State / ViewModels]
  VM --> Bridge[SlicingEngineBridge (Swift/C++ interop)]
  Bridge --> Core[libslic3r static lib - AGPLv3, reused from BambuStudio]
  VM --> Renderer[Metal Renderer]
  Renderer --> Core
  VM --> Net[Printer Communication - Swift, ported from slic3r/Utils]
  VM --> Persist[3MF Project Persistence via SlicingEngineBridge]
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

## P3-003: Advanced slicing settings (printer/process/filament pickers, setting overrides, persistence)

Extends the existing profile/config machinery rather than inventing a
parallel settings model:

- **Profile pickers** (`SlicingSettingsView`): `BambuProfileLoader` gained
  `instantiableProfileNames(type:)` and `isCompatible(_:withMachine:)`,
  reading the same `"type"`/`"instantiation"`/`"compatible_printers"`
  fields BambuStudio's own preset picker filters on (`PresetBundle.cpp`).
  Process/filament pickers are filtered live to the selected machine's
  compatible set; switching machines snaps any now-incompatible
  selection to the first compatible option.
- **Overrides**: `SlicingJob.ProfileSelection` gained an
  `overrides: [String: String]` dict keyed by real libslic3r config
  option names (`layer_height`, `wall_loops`, `sparse_infill_density`,
  `enable_support`, `nozzle_temperature`, `hot_plate_temp` —
  `SlicingJob.overridableKeys`), applied last in
  `resolvedConfigEntries` so they win over the selected process/filament
  profile's own values. The settings UI reads displayed values from the
  same `resolvedConfigEntries` merge (`effectiveValues`), so an untouched
  slider shows the real profile default, not a hardcoded guess.
- **Validation** (requirement: "invalid combinations are rejected
  safely"): `SlicingJob.validate` checks `compatible_printers` and is
  called automatically inside `resolvedConfigEntries` — every slice and
  every save is validated server-side, not just the UI picker's
  client-side filtering (defense in depth: a saved project with a
  stale/corrupted selection still fails safely with
  `BambuProfileError.incompatibleProfile` instead of silently slicing
  with a mismatched profile or crashing the engine).
- **Persistence** (requirement: "settings and overrides persist across
  project saves and reloads"): reuses libslic3r's own project-config
  channel rather than an invented side-file. `nsa1_store_3mf` now also
  takes `config_entries` and writes the fully resolved+repaired
  `DynamicPrintConfig` into the 3MF's `Metadata/Slic3r_PE.config` entry
  (the real `_add_print_config_file_to_archive` writer BambuStudio's own
  3mf exporter uses). Profile *choice* (not just numeric overrides) is
  recorded via the same real engine keys BambuStudio itself uses to
  remember a project's preset selection: `printer_settings_id`,
  `print_settings_id`, `filament_settings_id`
  (`PrintConfig.cpp`).

  **Upstream gap found and worked around:** `Slic3r::load_3mf`'s
  `DynamicPrintConfig&` out-param is never actually populated — the
  archive-entry branch that would read `Metadata/Slic3r_PE.config` back
  (`PRINT_CONFIG_FILE` in `3mf.cpp`'s importer) is inside a
  `/* ... */`-commented-out block. The write path
  (`_add_print_config_file_to_archive`) is live; the matching read path
  isn't — BambuStudio's own GUI apparently restores project settings
  through its separate `src/slic3r/GUI` preset-bundle layer instead,
  which isn't vendored here (ARCHITECTURE.md P0-005 — GUI layer
  deliberately out of scope). Worked around in `nsa1_load_3mf_config` by
  reading the same archive entry directly, using the same
  `miniz_extension.hpp` helpers (`open_zip_reader`/`mz_zip_reader_*`)
  `3mf.cpp` itself uses internally, then parsing it with the real
  engine's own `ConfigBase::load_from_gcode_string_legacy` — the exact
  format `_add_print_config_file_to_archive` writes (semicolon-commented
  `; key = value` lines), not a reimplemented parser.

  One real format subtlety hit and handled: `filament_settings_id` is
  libslic3r's `coStrings` (array) type, whose real `serialize()`
  (`ConfigOptionStrings`, `Config.cpp`) C-style-quotes any element
  containing a space (`escape_strings_cstyle`) — every vendored A1
  filament profile name has one. `SlicingJob.restoreSelection` strips
  that single surrounding quote pair back off.

- **Settings UI → real G-code**: a `layer_height` override measurably
  changes the real engine's layer count (verified:
  `SlicingJobTests.testLayerHeightOverrideChangesRealLayerCount`, 100 →
  249 layers for 0.2mm → 0.08mm on a 20mm cube) — proving overrides
  reach `Print::process()`, not just the config dictionary.
- **AMS Lite compatibility**: every vendored A1 filament profile is
  already one AMS Lite validates against (RESEARCH-P0-008.md); the
  filament picker's `instantiableProfileNames(type: "filament")` list
  *is* the AMS-Lite-compatible list by construction — no separate filter
  needed (SPEC.md A1-only, single-material scope; P2-006 handles AMS
  slot mapping separately once a filament is chosen).
- **Per-nozzle custom G-code templates**: already resolved by P1-008's
  follow-up fix (see above, `BambuProfileLoader.resolve`'s `include`
  support) — the settings UI's machine picker selects between the A1
  nozzle variants, each with its own real `include`d G-code templates,
  not just a `nozzle_diameter` number.
- **Independent code review** (subagent): confirmed C++ memory safety
  (`nsa1_load_3mf_config`'s zip-archive handling closes on every path,
  `nsa1_free_config_entries` matches the allocation pattern) and flagged
  one real gap — `SlicingSettingsView`'s machine-switch snap logic fell
  back to keeping a now-incompatible process/filament selection if no
  compatible replacement existed, deferring the failure to the next
  slice/save instead of surfacing it immediately. Fixed: that branch now
  sets `document.lastError` right away. Unreachable with the real
  vendored A1 closure (every nozzle variant has ≥1 compatible process and
  filament, verified directly), but cheap to harden regardless.

## P9-007: macOS deployment-target / zstd linker warning fix

**Symptom**: `swift build` emitted "building for macOS-14.0, but linking
with dylib '/opt/homebrew/opt/zstd/lib/libzstd.1.dylib' which was built
for newer version 26.0".

**Root cause, traced to the actual symbol need, not just the warning**:
`Package.swift`'s flat linker-flags list (see P0-005/P1-003 above)
hardcoded `/opt/homebrew/lib/libzstd.1.5.7.dylib`. Confirmed via `nm -u`
that two of the vendored static deps have genuinely undefined `ZSTD_*`
symbols at their own archive level: `libboost_iostreams.a` (Boost's
optional zstd `iostreams` filter, `boost_iostreams_option(...)` in
`libs/iostreams/CMakeLists.txt`, gated on `find_package(zstd)`) and
`libblosc.a` (OpenVDB's Blosc codec dependency — Blosc's own
`internal-complibs` normally bundles zstd 1.4.1 as a `OBJECT` library,
but that only gets absorbed into the final link automatically through
CMake's own target graph; our Swift linker line is a hand-computed flat
list of `.a` paths — see P0-005 — so those internal objects never reach
the final link, and Blosc's own compiled code still references bare
`ZSTD_*` symbols that have to come from *somewhere* in that flat list).
Both deps found Homebrew's zstd via plain `find_library`/`find_package`
at CMake configure time, because every other one of this project's ~25
third-party deps is built from source against
`CMAKE_OSX_DEPLOYMENT_TARGET=14.0` (`Scripts/build-libslic3r.sh`) — zstd
was the one dependency nobody vendored, so it fell through to whatever
the build host happens to have installed via Homebrew, a dylib that
tracks the *host's* SDK (observed: 26.0) rather than this project's
deployment target. Upstream BambuStudio's own `deps/CMakeLists.txt`
doesn't vendor zstd either — a comment there
(`CMakeLists.txt:525-527`) notes "on Windows/macOS zstd comes from the
prebuilt deps / vcpkg", i.e. upstream's *official* build pulls it from a
separately-fetched prebuilt dependency bundle this from-source build
never used.

**Fix**: build zstd 1.5.7 the same way as every other dependency.
`Scripts/build-libslic3r.sh` now injects a `deps/ZSTD/ZSTD.cmake`
(`bambustudio_add_cmake_project(ZSTD ...)`, static-only:
`ZSTD_BUILD_SHARED=OFF`/`ZSTD_BUILD_STATIC=ON`, pinned tarball +
SHA-256) into the vendored (gitignored, freshly-cloned) `deps/CMakeLists.txt`,
and patches `Boost.cmake`/`Blosc.cmake` to add `DEPENDS ${ZSTD_PKG}` so
it's always built and installed (into the same
`BambuStudio_deps/usr/local` prefix as everything else, found first via
the `CMAKE_PREFIX_PATH` every `bambustudio_add_cmake_project` dep
already receives) before either consumer configures. `Package.swift`
now links the resulting `.../usr/local/lib/libzstd.a` instead of the
Homebrew dylib; the now-unneeded `-rpath /opt/homebrew/lib` linker flag
was removed (nothing else used it). For checkouts whose deps were
already built before this fix existed, the script also force-rebuilds
just `dep_ZSTD`/`dep_Boost`/`dep_Blosc` (deletes their stale
`ExternalProject` prefix dirs so their cached `CMakeCache.txt` — which
would otherwise keep resolving Homebrew's copy — gets regenerated),
leaving the other ~23 already-built deps untouched.

**Side effect, verified deterministic (not a race)**: after the fix,
`libboost_iostreams.a` has *zero* undefined `ZSTD_*` symbols — Boost's
`iostreams_option` macro for zstd hardcodes a check for the
`zstd::libzstd_shared` imported CMake target specifically; since zstd was
built static-only (`ZSTD_BUILD_SHARED=OFF`, matching this project's
`BUILD_SHARED_LIBS=OFF` policy for every other dep), that target never
exists, so `BOOST_IOSTREAMS_ENABLE_ZSTD` evaluates `OFF` regardless of
`zstd_FOUND` — confirmed via the generated `CMakeCache.txt`, not
inferred. This is harmless: `libslic3r` never calls
`boost::iostreams::zstd_compressor`/`zstd_decompressor` anywhere (grepped
the full vendored source tree, zero hits) — the filter was always dead
weight pulled in opportunistically by whatever zstd the build host had.
Blosc's undefined symbols are unaffected by this (Blosc's own
`find_library(zstd)` path is independent of Boost's CMake-target-based
check) and are satisfied by the new `libzstd.a` at final link,
regardless of which internal-vs-external choice Blosc's own CMake
options believe they made — the linker only cares that the symbol names
match, and both Blosc's bundled zstd-1.4.1 sources and upstream zstd
1.5.7 export the same stable `ZSTD_*` C API.

**Verification**:
- `swift build` (clean, `rm -rf .build` first): zero zstd/deployment
  warnings (grepped full log).
- `otool -l .build/.../NativeSlicerA1 | grep -A4 LC_BUILD_VERSION`:
  `minos 14.0 sdk 14.0`.
- `otool -L .build/.../NativeSlicerA1`: every entry is `/usr/lib/*` or
  `/System/Library/Frameworks/*` (SDK-provided, always matches the
  runtime OS) — zero `/opt/homebrew` or other third-party dylibs.
- `swift test`: all 43 tests still pass (no behavioral change — zstd was
  never on a code path `libslic3r` actually exercises for this project's
  STL/3MF/G-code pipeline).
