# Native Calibration Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native, non-printing SwiftUI workflows that generate real Bambu A1 calibration G-code for flow ratio, pressure advance, temperature, retraction, and maximum volumetric speed through the already-linked `libslic3r` engine.

**Architecture:** Keep the public Swift surface small: immutable `CalibrationRequest`/`CalibrationResult` values, `CalibrationJob` for validation/defaults/request construction, and a sheet that owns only UI state. Add one narrow, typed C ABI operation rather than exposing C++ `Model`, `Print`, `GCode`, `DynamicPrintConfig`, or `CustomGCode` types. The bridge owns upstream model/resource loading, applies calibration-specific object/config/custom-G-code state before calling the existing `Print::apply → validate → process → export_gcode` pipeline, and returns existing real toolpath data plus a small owned manifest for preview/explanation.

**Tech Stack:** Swift 5.10 / SwiftUI / XCTest / SwiftPM; C++17 C ABI bridge; vendored BambuStudio `libslic3r` `v02.08.04.61`; Metal viewport (existing toolpath rendering).

**Spec:** `SPEC.md` §20; user-requested workflow order and constraints; `FEATURE_PARITY.md` §13; `ARCHITECTURE.md` P1-008/P3-003; `TODO.md` P3-002.

## Global Constraints

- macOS 14.0 minimum (`Package.swift`, `Scripts/build-libslic3r.sh`); never raise it for this feature.
- Reuse the pinned upstream implementations: `vendor/BambuStudio` is built from BambuStudio `v02.08.04.61`; do not reimplement mature slicing or geometry code in Swift.
- Preserve originals: generated calibration projects/models are separate from the open `ProjectDocument`; no imported source mesh is repaired or destructively modified.
- Every flow must validate selected printer/process/filament compatibility through `SlicingJob.validate` before bridge invocation.
- Capability must be explicit: no calibration request may infer A1 firmware support from `printer_model`; a missing capability is an actionable unsupported/unknown error, not a generated G-code guess.
- Never invoke printer upload, start-print, or MQTT printer commands. Generation/export only.
- Bundle only reviewed upstream calibration resources; retain AGPLv3 notices and separately review/attribute the Orca PA pattern's GPLv3 provenance before using that resource. Prefer BambuStudio resources whenever the equivalent exists.
- All permanent tests exercise the real linked engine and bundled upstream resource, not mocked G-code or string-only forwarding checks.
- Maintain C ABI ownership rules: all heap-backed bridge results have a matching `nsa1_free_*`; every error path frees local C++/C allocations.

## Review Focus

1. **Incompatible profile or unconfirmed capability:** reject before model loading/slicing and show an actionable error; test owns this in Task 2.
2. **Calibration range invalidity:** start/end/step must be finite, positive-step, and produce a bounded number of blocks; test owns this in Task 2.
3. **Flow calibration per-object ratio:** different 3MF calibration objects must produce measurably different real extrusion while preserving XY geometry; test owns this in Task 5.
4. **Layer/block transition alignment:** temperature/retraction/volumetric values must change at real toolpath Z boundaries, not after-export text positions; tests own this in Tasks 7–9.
5. **Resource/ABI failure:** a missing or malformed bundled resource must return a bridge error without mutating the open document or triggering a printer action; test owns this in Task 4.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/NativeSlicerA1/Calibration.swift` | Pure Swift request/result/value validation, selected-profile compatibility gate, resource lookup, and bridge orchestration; no view state. |
| `Sources/NativeSlicerA1/CalibrationView.swift` | One sheet with workflow picker, workflow-specific controls, human explanation/preview, generate/export action; uses `@State private` only for editing state and `@Binding` for the sheet presentation. |
| `Sources/NativeSlicerA1/ProjectDocument.swift` | Holds a generated `CalibrationResult?` separately from the user scene; runs `CalibrationJob.generate` off the main actor; never replaces normal meshes/objects. |
| `Sources/NativeSlicerA1/ContentView.swift` | Adds a labeled “Calibration…” toolbar command/sheet entry. |
| `Sources/NativeSlicerA1/SlicingEngineBridge.swift` | Swift C-ABI translation for fixed-layout request/manifest/toolpath result and frees native allocation. |
| `Sources/CSlic3rBridge/include/CSlic3rBridge.h` | C-compatible request enum/struct/result/manifest declarations and ownership documentation. |
| `Sources/CSlic3rBridge/CSlic3rBridge.cpp` | Converts C request to upstream `Model`/`DynamicPrintConfig`; invokes calibration helper plus existing `Print` pipeline; owns manifest/toolpath/error allocation. |
| `Sources/CSlic3rBridge/Calibration.cpp` | Bridge-private adapter around `Slic3r::CalibPressureAdvancePattern` and carefully lifted, minimal model/config construction from upstream `GUI/Plater.cpp`; never imports GUI/`CalibUtils` or printer code. |
| `Sources/CSlic3rBridge/Calibration.hpp` | Bridge-private C++ request/manifest helper declarations; no public ABI types. |
| `Sources/NativeSlicerA1/Resources/Calibration/...` | Reviewed BambuStudio calibration assets: flow pass 1/2 3MF, temperature/retraction STL, volumetric STEP, PA model only after provenance review. |
| `Tests/NativeSlicerA1Tests/CalibrationJobTests.swift` | Validation/unit tests and five real-engine output assertions. |
| `THIRD_PARTY_LICENSES.md` | Exact source/version/license/attribution record for every copied calibration asset/code fragment. |
| `ARCHITECTURE.md`, `TODO.md`, `SESSION.md`, `FEATURE_PARITY.md` | Decision, task state, verification, and citation updates. |

## Public Interfaces

Swift values (Task 2):

```swift
enum CalibrationWorkflow: String, CaseIterable, Codable {
    case flowRate, pressureAdvance, temperature, retraction, maxVolumetricSpeed
}

struct CalibrationRequest: Equatable, Codable {
    var workflow: CalibrationWorkflow
    var start: Double
    var end: Double
    var step: Double
    var printNumbers: Bool
    var selection: SlicingJob.ProfileSelection
}

struct CalibrationBlock: Equatable {
    let ordinal: Int
    let value: Double
    let startZ: Double?
    let endZ: Double?
}

struct CalibrationResult {
    let request: CalibrationRequest
    let blocks: [CalibrationBlock]
    let toolpath: [ToolpathSegment]
    let outputURL: URL
}

enum CalibrationError: LocalizedError {
    case invalidRange(start: Double, end: Double, step: Double)
    case unsupportedCapability(CalibrationWorkflow, String)
    case missingResource(String)
}
```

C ABI (Task 3; exact field names must remain fixed after Task 3):

```c
typedef enum {
    NSA1_CALIB_FLOW_RATE,
    NSA1_CALIB_PRESSURE_ADVANCE,
    NSA1_CALIB_TEMPERATURE,
    NSA1_CALIB_RETRACTION,
    NSA1_CALIB_MAX_VOLUMETRIC_SPEED
} NSA1CalibrationWorkflow;

typedef struct {
    NSA1CalibrationWorkflow workflow;
    double start;
    double end;
    double step;
    uint8_t print_numbers;
    const char *resource_path;
    const NSA1ConfigEntry *config_entries;
    size_t config_entry_count;
} NSA1CalibrationRequest;

typedef struct { size_t ordinal; double value; double start_z; double end_z; } NSA1CalibrationBlock;
typedef struct {
    NSA1Toolpath *toolpath;
    NSA1CalibrationBlock *blocks;
    size_t block_count;
} NSA1CalibrationResult;

int nsa1_generate_calibration_gcode(
    const NSA1CalibrationRequest *request,
    const char *out_gcode_path,
    NSA1CalibrationResult **out_result,
    char **out_error);
void nsa1_free_calibration_result(NSA1CalibrationResult *result);
```

`resource_path` is a trusted app-bundle path selected by `CalibrationJob`; it is never user-supplied arbitrary file input. The bridge must still return a controlled error if it does not load.

### Task 1: License-review and bundle the exact BambuStudio calibration resources

**Files:**
- Create: `Sources/NativeSlicerA1/Resources/Calibration/NOTICE.md`
- Create: asset copies under `Sources/NativeSlicerA1/Resources/Calibration/`
- Modify: `Package.swift`
- Modify: `THIRD_PARTY_LICENSES.md`
- Modify: `TODO.md`

**Consumes:** Exact resource inventory from `FEATURE_PARITY.md` §13 / upstream source:
`resources/calib/filament_flow/flowrate-test-pass{1,2}.3mf`,
`temperature_tower/temperature_tower.stl`,
`retraction/retraction_tower.stl`,
`volumetric_speed/SpeedTestStructure.step`.

**Produces:** Read-only app-bundle resource paths owned by `CalibrationJob`; exact license/notice record. Do **not** copy Orca PA material until the separate GPLv3 provenance check in Task 6 is complete.

- [ ] **Step 1: Write the failing resource-availability test**

```swift
func testBundledCalibrationResourcesExist() throws {
    for name in ["flowrate-test-pass1", "flowrate-test-pass2", "temperature_tower", "retraction_tower", "SpeedTestStructure"] {
        XCTAssertNotNil(CalibrationResources.url(named: name))
    }
}
```

- [ ] **Step 2: Run the test to verify RED**

Run: `swift test --filter CalibrationJobTests/testBundledCalibrationResourcesExist`

Expected: compile failure because `CalibrationResources` does not exist.

- [ ] **Step 3: Copy only the named BambuStudio files and record provenance**

Copy the exact files from `.research/BambuStudio/resources/calib/` without alteration. `NOTICE.md` must name BambuStudio tag `v02.08.04.61`/commit `f5e51a2`, original relative path, AGPLv3 source, and the local destination for each asset. Add those exact rows to `THIRD_PARTY_LICENSES.md`. Add `.copy("Resources/Calibration")` only if SwiftPM does not already include the parent `Resources` directory recursively.

- [ ] **Step 4: Implement the smallest resource lookup**

```swift
enum CalibrationResources {
    static func url(named name: String) -> URL? {
        let extensions = ["3mf", "stl", "step"]
        return extensions.lazy.compactMap { Bundle.module.url(forResource: name, withExtension: $0, subdirectory: "Calibration") }.first
    }
}
```

Use nested subdirectories only if `Bundle.module` requires them; adjust test names to the actual bundle layout.

- [ ] **Step 5: Run the resource test to verify GREEN**

Run: `swift test --filter CalibrationJobTests/testBundledCalibrationResourcesExist`

Expected: PASS, resolving all five logical assets from `Bundle.module`.

- [ ] **Step 6: Commit this self-contained licensing/resource milestone**

```bash
git add Package.swift Sources/NativeSlicerA1/Resources/Calibration THIRD_PARTY_LICENSES.md TODO.md Tests/NativeSlicerA1Tests/CalibrationJobTests.swift
git commit -m "feat(calibration): bundle reviewed upstream test models"
```

### Task 2: Define validated calibration requests and capability gate (test-first)

**Files:**
- Create: `Sources/NativeSlicerA1/Calibration.swift`
- Create: `Tests/NativeSlicerA1Tests/CalibrationJobTests.swift`

**Consumes:** `SlicingJob.ProfileSelection`, `BambuProfileLoader`, `CalibrationResources` (Task 1).

**Produces:** `CalibrationWorkflow`, `CalibrationRequest`, `CalibrationBlock`, `CalibrationError`, and `CalibrationJob.validate(_:loader:capabilities:)` for all later tasks.

- [ ] **Step 1: Write failing range/compatibility/capability tests**

```swift
func testFlowRateRejectsNonPositiveStep() throws {
    let request = CalibrationRequest(workflow: .flowRate, start: 0.95, end: 1.05, step: 0, printNumbers: false, selection: .init())
    XCTAssertThrowsError(try CalibrationJob.validate(request, loader: loader, capabilities: .allSupported)) { error in
        XCTAssertEqual(error as? CalibrationError, .invalidRange(start: 0.95, end: 1.05, step: 0))
    }
}

func testPressureAdvanceRejectsUnknownCapability() throws {
    let request = CalibrationRequest(workflow: .pressureAdvance, start: 0, end: 0.02, step: 0.002, printNumbers: true, selection: .init())
    XCTAssertThrowsError(try CalibrationJob.validate(request, loader: loader, capabilities: .a1Unknown))
}

func testCalibrationRejectsIncompatibleProfileBeforeResourceAccess() throws {
    var selection = SlicingJob.ProfileSelection()
    selection.process = "incompatible profile fixture"
    let request = CalibrationRequest(workflow: .temperature, start: 230, end: 220, step: 5, printNumbers: false, selection: selection)
    XCTAssertThrowsError(try CalibrationJob.validate(request, loader: loader, capabilities: .allSupported))
}
```

- [ ] **Step 2: Run tests to verify RED**

Run: `swift test --filter CalibrationJobTests`

Expected: compile failure because the new domain types do not exist.

- [ ] **Step 3: Implement minimal pure validation**

`CalibrationJob.validate` first calls `SlicingJob.validate(request.selection, loader:)`; rejects non-finite ranges, `step <= 0`, `end < start`, or more than 200 blocks; then checks an explicit injected `CalibrationCapabilities` value. A1’s initial capability source is `.unknown` for PA until evidence is supplied — UI must render a non-dismissable explanation and cannot call the bridge. Do not call MQTT.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `swift test --filter CalibrationJobTests`

Expected: all three tests pass with expected error cases.

### Task 3: Add the narrow calibration C ABI without exposing C++ internals

**Files:**
- Modify: `Sources/CSlic3rBridge/include/CSlic3rBridge.h`
- Modify: `Sources/NativeSlicerA1/SlicingEngineBridge.swift`
- Modify: `Tests/NativeSlicerA1Tests/CalibrationJobTests.swift`

**Consumes:** C structs/signatures from this plan’s Public Interfaces section; existing `NSA1Toolpath` allocation/free conventions.

**Produces:** Swift `SlicingEngine.generateCalibrationGCode(request:configEntries:outputPath:) throws -> (toolpath:[ToolpathSegment], blocks:[CalibrationBlock])`; native stub returns a controlled “not implemented” only until Task 4 installs the helper.

- [ ] **Step 1: Write the failing bridge ownership/error test**

```swift
func testMissingCalibrationResourceThrowsBridgeError() throws {
    let request = try CalibrationJob.validatedRequest(.temperature, start: 230, end: 220, step: 5, loader: loader)
    XCTAssertThrowsError(try SlicingEngine.generateCalibrationGCode(
        request: request, resourceURL: URL(fileURLWithPath: "/missing/calibration.stl"),
        configEntries: try SlicingJob.resolvedConfigEntries(loader: loader), outputPath: temporaryGCode.path
    ))
}
```

- [ ] **Step 2: Run test to verify RED**

Run: `swift test --filter CalibrationJobTests/testMissingCalibrationResourceThrowsBridgeError`

Expected: compile failure because `generateCalibrationGCode` does not exist.

- [ ] **Step 3: Add ABI structs/free functions and Swift translation**

The bridge must initialize every `out_*` to null/zero before work, convert all failure messages through `nsa1_free_string`, and free `NSA1CalibrationResult` exactly once via `nsa1_free_calibration_result`. Swift must map the manifest values to `[CalibrationBlock]`, then free native memory on every result path.

- [ ] **Step 4: Implement only the missing-resource failure path**

Before creating a `Model`, require `std::filesystem::exists(request->resource_path)`; return `-1` and a descriptive allocated error for missing/unreadable input. This lets the test prove C-to-Swift failure ownership before any successful workflow exists.

- [ ] **Step 5: Run test to verify GREEN**

Run: `swift test --filter CalibrationJobTests/testMissingCalibrationResourceThrowsBridgeError`

Expected: PASS with a `SlicingEngineError.sliceFailed` containing “missing calibration resource”.

### Task 4: Implement shared bridge-private model/config construction

**Files:**
- Create: `Sources/CSlic3rBridge/Calibration.hpp`
- Create: `Sources/CSlic3rBridge/Calibration.cpp`
- Modify: `Sources/CSlic3rBridge/CSlic3rBridge.cpp`
- Modify: `Sources/CSlic3rBridge/include/CSlic3rBridge.h`
- Modify: `Tests/NativeSlicerA1Tests/CalibrationJobTests.swift`

**Consumes:** Task 3 ABI; existing `build_full_config`, `repair_enum_keys_map`, `nsa1_slice_to_gcode` model/Print pipeline; upstream GUI behavior cited in `FEATURE_PARITY.md` §13.

**Produces:** `CalibrationBridge::generate(const NSA1CalibrationRequest&, const char*)`, which loads a trusted resource to `Slic3r::Model`, overlays a repaired `DynamicPrintConfig`, returns real engine toolpath/blocks, and never references `GUI`, `CalibUtils`, `send_to_print`, network code, or `ProjectDocument`.

- [ ] **Step 1: Write the failing real-engine smoke test**

```swift
func testTemperatureCalibrationProducesRealToolpath() throws {
    let result = try CalibrationJob.generate(.temperature(start: 230, end: 220, step: 5), loader: loader, outputURL: temporaryGCode)
    XCTAssertFalse(result.toolpath.isEmpty)
    XCTAssertEqual(result.blocks.map(\.value), [230, 225, 220])
    XCTAssertTrue(try String(contentsOf: temporaryGCode).contains("M104"))
}
```

- [ ] **Step 2: Run the test to verify RED**

Run: `swift test --filter CalibrationJobTests/testTemperatureCalibrationProducesRealToolpath`

Expected: fail because no successful bridge generator is installed.

- [ ] **Step 3: Factor, do not duplicate, normal slicer setup**

Extract only the shared C++ helpers that build a repaired full print config, load an upstream resource model, call `Print::apply/validate/process/export_gcode`, and translate `GCodeProcessorResult::moves` to `NSA1Toolpath`. Keep `nsa1_slice_to_gcode` behavior byte-for-byte unchanged; both operations call the same helpers.

- [ ] **Step 4: Implement exact block manifest allocation**

For every requested block allocate one `NSA1CalibrationBlock` with ordinal/value and real Z boundaries when the implementation knows them. Never derive user-visible block count from raw string matches in emitted G-code.

- [ ] **Step 5: Run the smoke test to verify GREEN**

Run: `swift test --filter CalibrationJobTests/testTemperatureCalibrationProducesRealToolpath`

Expected: PASS: nonempty toolpath and a three-entry manifest for 230/225/220.

### Task 5: Implement flow-rate calibration first (two-pass resource model)

**Files:**
- Modify: `Sources/CSlic3rBridge/Calibration.cpp`
- Modify: `Sources/NativeSlicerA1/Calibration.swift`
- Modify: `Tests/NativeSlicerA1Tests/CalibrationJobTests.swift`

**Consumes:** `flowrate-test-pass1.3mf`/`flowrate-test-pass2.3mf`; upstream source `BambuStudio/src/slic3r/GUI/Plater.cpp:21245-21319` (equivalent Orca `Plater.cpp:12979-13137`).

**Produces:** `.flowRate` selecting pass 1/coarse versus pass 2/fine from the validated request; applies real per-object `print_flow_ratio` to the loaded `Model` before `Print::process`.

- [ ] **Step 1: Write the failing flow-difference test**

```swift
func testFlowRatePassOneChangesExtrusionByObjectRatio() throws {
    let result = try CalibrationJob.generate(.flowRate(start: 0.95, end: 1.05, step: 0.05), loader: loader, outputURL: temporaryGCode)
    XCTAssertEqual(result.blocks.map(\.value), [0.95, 1.0, 1.05])
    let positiveExtrusionByBlock = try GCodeAssertions.positiveExtrusionByCalibrationBlock(temporaryGCode)
    XCTAssertEqual(positiveExtrusionByBlock.count, 3)
    XCTAssertNotEqual(positiveExtrusionByBlock[0], positiveExtrusionByBlock[2])
}
```

- [ ] **Step 2: Run test to verify RED**

Run: `swift test --filter CalibrationJobTests/testFlowRatePassOneChangesExtrusionByObjectRatio`

Expected: fail because `.flowRate` is not implemented.

- [ ] **Step 3: Lift only upstream model edits**

Load Bambu’s pass 1/2 3MF with `load_3mf`; apply each requested ratio to the corresponding upstream `ModelObject`’s config using the exact `print_flow_ratio` key/value behavior read from upstream `Plater::calib_flowrate`; reject requests whose requested block count does not fit the resource’s real object count. Do not create synthetic cube geometry.

- [ ] **Step 4: Run focused and full tests to verify GREEN**

Run: `swift test --filter CalibrationJobTests/testFlowRatePassOneChangesExtrusionByObjectRatio && swift test`

Expected: focused test and the existing full suite pass.

### Task 6: Implement pressure-advance using the upstream engine generator

**Files:**
- Modify: `Sources/CSlic3rBridge/Calibration.cpp`
- Modify: `Sources/NativeSlicerA1/Calibration.swift`
- Modify: `Sources/NativeSlicerA1/CalibrationView.swift`
- Modify: `Tests/NativeSlicerA1Tests/CalibrationJobTests.swift`
- Modify: `THIRD_PARTY_LICENSES.md`

**Consumes:** `Slic3r::CalibPressureAdvancePattern` public API: Bambu `Calib.hpp:302-315`, `Calib.cpp:498-653`; capability gate from Task 2.

**Produces:** `.pressureAdvance` pattern generation with actual `CustomGCode::Info` installed on the bridge-owned `Model` before slicing; visible capability warning when support is unknown/false.

- [ ] **Step 1: Write a failing PA marker test**

```swift
func testPressureAdvancePatternEmitsOrderedRequestedValues() throws {
    let result = try CalibrationJob.generate(.pressureAdvance(start: 0, end: 0.004, step: 0.002, printNumbers: true), loader: loader, capabilities: .allSupported, outputURL: temporaryGCode)
    XCTAssertEqual(result.blocks.map(\.value), [0, 0.002, 0.004])
    XCTAssertTrue(try GCodeAssertions.containsOrderedPressureAdvanceValues([0, 0.002, 0.004], in: temporaryGCode))
    XCTAssertFalse(result.toolpath.isEmpty)
}
```

- [ ] **Step 2: Run test to verify RED**

Run: `swift test --filter CalibrationJobTests/testPressureAdvancePatternEmitsOrderedRequestedValues`

Expected: fail because `.pressureAdvance` bridge dispatch is absent.

- [ ] **Step 3: Verify/record PA asset provenance before copying any asset**

Read Bambu’s exact source resource license/notice and Orca’s GPLv3 PA-pattern attribution (`.research/OrcaSlicer/README.md:232-237`). Prefer upstream Bambu `pa_pattern.3mf` only if its exact provenance is sufficient; otherwise generate the pattern through `CalibPressureAdvancePattern` without copying an Orca asset. Update `THIRD_PARTY_LICENSES.md` with actual checked file paths.

- [ ] **Step 4: Call the actual upstream class inside the bridge**

Construct `Calib_Params` from the request, construct `CalibPressureAdvancePattern(params, config, is_bbl_machine, model, origin)`, invoke `generate_custom_gcodes(config, is_bbl_machine, model, origin)`, then slice that same model through Task 4’s helper. Never hand-generate PA text in Swift or post-edit G-code.

- [ ] **Step 5: Run focused and full tests to verify GREEN**

Run: `swift test --filter CalibrationJobTests/testPressureAdvancePatternEmitsOrderedRequestedValues && swift test`

Expected: focused PA test and full suite pass. If the active A1 capability is unknown in the shipped capability source, test the supported path only through injected `.allSupported`; UI tests assert that production default blocks generation and explains why.

### Task 7: Implement temperature tower via model/config-range bridge adapter

**Files:**
- Modify: `Sources/CSlic3rBridge/Calibration.cpp`
- Modify: `Sources/NativeSlicerA1/Calibration.swift`
- Modify: `Tests/NativeSlicerA1Tests/CalibrationJobTests.swift`

**Consumes:** Bambu `temperature_tower.stl`; upstream Bambu `Plater.cpp:21320-21384` / Orca `Plater.cpp:13138-13217`.

**Produces:** `.temperature` model preparation and engine-native per-block temperature custom G-code/config state before `Print::process`.

- [ ] **Step 1: Write the failing real Z-transition test**

```swift
func testTemperatureTowerChangesTemperatureAtToolpathBlockBoundaries() throws {
    let result = try CalibrationJob.generate(.temperature(start: 230, end: 220, step: 5), loader: loader, outputURL: temporaryGCode)
    XCTAssertEqual(result.blocks.map(\.value), [230, 225, 220])
    XCTAssertTrue(try GCodeAssertions.temperatureTransitions([230, 225, 220], alignWith: result.blocks, gcode: temporaryGCode))
    XCTAssertTrue(result.blocks.allSatisfy { $0.startZ != nil && $0.endZ != nil })
}
```

- [ ] **Step 2: Run test to verify RED**

Run: `swift test --filter CalibrationJobTests/testTemperatureTowerChangesTemperatureAtToolpathBlockBoundaries`

Expected: fail because `.temperature` is not implemented.

- [ ] **Step 3: Adapt only the upstream preparation logic**

Load Bambu’s STL; perform the same block-height/cut/config computation shown in `Plater::calib_temptue`, but retain all data inside bridge-private C++ (no GUI types). Install temperature custom-G-code/config state before normal slicing. If the only viable upstream API is absent from `libslic3r`, stop and record the exact missing API rather than inserting `M104` into exported text.

- [ ] **Step 4: Run focused and full tests to verify GREEN**

Run: `swift test --filter CalibrationJobTests/testTemperatureTowerChangesTemperatureAtToolpathBlockBoundaries && swift test`

Expected: both pass, commands align with declared Z ranges.

### Task 8: Implement retraction tower via model/config-range bridge adapter

**Files:**
- Modify: `Sources/CSlic3rBridge/Calibration.cpp`
- Modify: `Sources/NativeSlicerA1/Calibration.swift`
- Modify: `Tests/NativeSlicerA1Tests/CalibrationJobTests.swift`

**Consumes:** Bambu `retraction_tower.stl`; upstream Bambu `Plater.cpp:21488-21580` / Orca `Plater.cpp:13293-13372`.

**Produces:** `.retraction` blocks whose real engine output contains distinct retraction/unretraction behavior.

- [ ] **Step 1: Write the failing retraction-output test**

```swift
func testRetractionTowerChangesRealRetractionEventsByBlock() throws {
    let result = try CalibrationJob.generate(.retraction(start: 0.2, end: 0.6, step: 0.2), loader: loader, outputURL: temporaryGCode)
    XCTAssertEqual(result.blocks.map(\.value), [0.2, 0.4, 0.6])
    XCTAssertTrue(try GCodeAssertions.retractionDeltasChange(at: result.blocks, gcode: temporaryGCode))
}
```

- [ ] **Step 2: Run test to verify RED**

Run: `swift test --filter CalibrationJobTests/testRetractionTowerChangesRealRetractionEventsByBlock`

Expected: fail because `.retraction` is not implemented.

- [ ] **Step 3: Adapt real upstream tower settings before slicing**

Load/cut Bambu’s resource and apply exactly the upstream retraction/shell/infill setup to calibration ranges. Do not rewrite `G10/G11` or E values after `export_gcode`; that would make the engine preview wrong.

- [ ] **Step 4: Run focused and full tests to verify GREEN**

Run: `swift test --filter CalibrationJobTests/testRetractionTowerChangesRealRetractionEventsByBlock && swift test`

Expected: both pass with per-block real output differences.

### Task 9: Implement maximum-volumetric-speed tower via `Flow` conversion

**Files:**
- Modify: `Sources/CSlic3rBridge/Calibration.cpp`
- Modify: `Sources/NativeSlicerA1/Calibration.swift`
- Modify: `Tests/NativeSlicerA1Tests/CalibrationJobTests.swift`

**Consumes:** Bambu `volumetric_speed/SpeedTestStructure.step`; upstream Bambu `Plater.cpp:21385-21487` / Orca `Plater.cpp:13218-13292`; upstream `Slic3r::Flow::mm3_per_mm`.

**Produces:** `.maxVolumetricSpeed` whose block ranges convert mm³/s into real engine speed constraints using upstream flow math.

- [ ] **Step 1: Write the failing feedrate-bound test**

```swift
func testVolumetricSpeedTowerUsesRequestedFlowCaps() throws {
    let result = try CalibrationJob.generate(.maxVolumetricSpeed(start: 5, end: 7, step: 1), loader: loader, outputURL: temporaryGCode)
    XCTAssertEqual(result.blocks.map(\.value), [5, 6, 7])
    XCTAssertTrue(try GCodeAssertions.volumetricRates(in: temporaryGCode, for: result.blocks).elementsEqual([5, 6, 7], by: approximatelyEqual))
}
```

- [ ] **Step 2: Run test to verify RED**

Run: `swift test --filter CalibrationJobTests/testVolumetricSpeedTowerUsesRequestedFlowCaps`

Expected: fail because `.maxVolumetricSpeed` is not implemented.

- [ ] **Step 3: Use upstream `Flow` math in C++**

Load/tessellate Bambu’s STEP resource through linked OpenCascade/libslic3r, calculate the exact line width/layer height and `Flow::mm3_per_mm()` conversion used by upstream, then apply per-block cap/range before engine slicing. Never treat mm³/s as a raw G-code feedrate.

- [ ] **Step 4: Run focused and full tests to verify GREEN**

Run: `swift test --filter CalibrationJobTests/testVolumetricSpeedTowerUsesRequestedFlowCaps && swift test`

Expected: both pass; test derives observed mm³/s from real extrusion geometry/feedrate, not raw string presence.

### Task 10: Add native SwiftUI calibration sheet, project persistence, and no-print smoke proof

**Files:**
- Create: `Sources/NativeSlicerA1/CalibrationView.swift`
- Modify: `Sources/NativeSlicerA1/ContentView.swift`
- Modify: `Sources/NativeSlicerA1/ProjectDocument.swift`
- Modify: `Sources/NativeSlicerA1/Calibration.swift`
- Modify: `Tests/NativeSlicerA1Tests/CalibrationJobTests.swift`

**Consumes:** Tasks 1–9 APIs and `CalibrationResult`.

**Produces:** a “Calibration…” sheet, native controls/explanation/preview, generated calibration result in document state, and no printer call path.

- [ ] **Step 1: Write the failing workflow-state test**

```swift
@MainActor
func testGeneratingCalibrationDoesNotReplaceSceneOrSendToPrinter() async throws {
    let document = documentWithRealCube()
    let originalObjectIDs = document.objects.map(\.id)
    try await document.generateCalibration(.flowRate(start: 0.95, end: 1.05, step: 0.05))
    XCTAssertEqual(document.objects.map(\.id), originalObjectIDs)
    XCTAssertNotNil(document.calibrationResult)
    XCTAssertNil(document.lastPrinterAction)
}
```

- [ ] **Step 2: Run test to verify RED**

Run: `swift test --filter CalibrationJobTests/testGeneratingCalibrationDoesNotReplaceSceneOrSendToPrinter`

Expected: compile failure because document calibration state/action does not exist.

- [ ] **Step 3: Implement document-owned calibration state**

Add `@Published private(set) var calibrationResult: CalibrationResult?`; run `CalibrationJob.generate` in `Task.detached`, just as `ProjectDocument.slice()` does; update main-actor state only after success. Do not add a printer API or any “Print” button. Persist a completed calibration’s request/result choice in project config only after a successful result is explicitly applied to the active profile; never overwrite the source profile JSON.

- [ ] **Step 4: Implement small SwiftUI sheet boundaries**

`CalibrationView` receives the document and an `isPresented` binding. Standard `Picker`/`TextField`/`Toggle` controls update private request state; a single `Button("Generate G-code")` invokes document generation and is disabled for invalid/unknown capability. Use labels and accessibility values for every control; no custom Metal gesture is required for this sheet.

- [ ] **Step 5: Run focused UI/state test and app smoke test**

Run: `swift test --filter CalibrationJobTests/testGeneratingCalibrationDoesNotReplaceSceneOrSendToPrinter && swift run NativeSlicerA1`

Expected: test passes; manually observe Calibration sheet opens, explains selected workflow, and only offers generation/export (never print/upload).

### Task 11: Final verification, documentation, independent review, commit/push

**Files:**
- Modify: `TODO.md`, `SESSION.md`, `ARCHITECTURE.md`, `FEATURE_PARITY.md`, `TESTING.md` (only if that file exists — do not create redundant docs)

- [ ] **Step 1: Run all focused calibration tests**

Run: `swift test --filter CalibrationJobTests`

Expected: all range/resource/capability and five real-engine workflow tests pass.

- [ ] **Step 2: Run full build and test suite**

Run: `swift build && swift test`

Expected: build success and every existing/new test passes.

- [ ] **Step 3: Smoke the actual app surface**

Run: `swift run NativeSlicerA1`

Expected: open the Calibration sheet, generate each capability-supported flow, confirm a G-code preview/toolpath appears and no upload/print action occurs. Report hardware limits truthfully: no physical A1 validation unless actually performed.

- [ ] **Step 4: Independent review**

Request a reviewer to check C ABI ownership/error paths, profile/capability gating, upstream-resource license notices, and the no-printer-action invariant. Resolve all evidence-backed findings.

- [ ] **Step 5: Update docs/task state and commit/push**

```bash
git add Sources Tests TODO.md SESSION.md ARCHITECTURE.md FEATURE_PARITY.md THIRD_PARTY_LICENSES.md docs/superpowers/plans/2026-10-11-calibration-workflows.md
git commit -m "feat(calibration): implement native engine-backed workflows"
git push
```

## Self-Review

- **Spec coverage:** Covers SPEC §20 flow ratio, pressure advance where supported, temperature/retraction; adds the explicitly requested max-volumetric workflow. Stringing/bed adhesion/dimensional/hole/connector/overhang tests remain outside the user’s stated immediate five and are not represented as finished work. Result storage is scoped to explicit profile application, then optional device polling, satisfying the “per printer/nozzle/filament” direction without assuming printer support.
- **Placeholder scan:** No TODO/TBD steps; all paths, API names, sources, commands, and expected failure/pass outcomes are defined.
- **Type consistency:** `CalibrationRequest` is the only Swift request passed to bridge translation; `NSA1CalibrationRequest` is only the C layout; both produce `CalibrationBlock`/`NSA1CalibrationBlock`. Existing `SlicingJob` remains profile/config owner.
- **Review-focus coverage:** Task 2 owns invalid/incompatible/unknown capability; Task 4 owns resource/ABI errors; Tasks 5–9 own real engine output and block-boundary correctness; Task 10 owns preservation/no-print behavior.
