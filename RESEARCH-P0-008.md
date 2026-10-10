## P0-008: AMS Lite Integration (External Spool/Filament System)

### Executive Summary

AMS Lite is a simplified filament storage and switching system for Bambu Lab printers (A1, A1M, P1P, etc.). Unlike the full AMS (Automatic Material System), AMS Lite is a **passive system with no heater, humidity sensors, or drying capability**. It serves as an intermediate solution between the full AMS and pure external spool operation, supporting **4 filament slots** just like the full AMS.

### Key Findings

#### 1. **Data Model: Slot Count & Structure**

- **AMS Lite has 4 slots** (slots 0–3), same as full AMS and AMS 2 Pro
- Each slot is identified by: `ams_id` (unit ID) and `slot_id` (0–3)
- Virtual/external spool uses special IDs: `255` (right) and `254` (left)
- Slot state is reported via MQTT `tray_exist_bits` bitmask

**Source Files:**
- `.research/BambuStudio/src/slic3r/GUI/DeviceCore/DevFilaSystem.h` - Lines 34–134 define `DevAmsTray` and `DevAms` classes with slot management
- `.research/BambuStudio/src/slic3r/GUI/DeviceCore/DevDefs.h` - AMS type enum:
  ```cpp
  enum DevAmsType : int {
    EXT_SPOOL = 0,        // External spool
    AMS = 1,              // Standard AMS
    AMS_LITE = 2,         // AMS Lite ← Our target
    N3F = 3,              // AMS 2 Pro
    N3S = 4,              // AMS HT
    AMS_LITE_MIXED = 5,   // AMS Lite variant for N9
  };
  ```

#### 2. **Slot State Reporting via MQTT**

BambuStudio receives filament/tray state via MQTT `push_status` messages under `print.ams`:

**Key fields:**
- `ams_exist_bits` – hexadecimal bitmask indicating which AMS units are present
- `tray_exist_bits` – bitmask indicating which slots physically have filament (e.g., "e" = binary 1110 = slots 1, 2, 3 occupied)
- `tray_now` – current active tray ID (0–3 for slots, or 255/254 for external spools)
- `ams[].id` – AMS unit identifier
- `ams[].tray[]` – array of tray objects with filament data:
  - `id` – slot ID (0–3)
  - `tag_uid` – RFID tag UID (for Bambu Lab branded filament)
  - `tray_color` – color in RRGGBBAA hex format
  - `tray_type` – filament material type (PLA, PETG, TPU, etc.)
  - `remain` – filament remaining percentage (0–100)
  - `bed_temp`, `nozzle_temp_min`, `nozzle_temp_max` – print temperatures
  - `xcam_info` – optional camera/visual slot state

**Source:** OpenBambuAPI MQTT documentation & `.research/BambuStudio/src/slic3r/GUI/DeviceCore/DevFilaSystem.h` (lines 275–294)

#### 3. **AMS Lite Feature Limitations vs. Full AMS**

| Feature | AMS Lite | Full AMS | AMS 2 Pro/HT |
|---------|----------|----------|-----------|
| **Slots** | 4 | 4 | 4 / 1 |
| **Humidity sensors** | ❌ None | ✅ 1–5 coarse scale | ✅ Yes |
| **Temperature sensors** | ❌ None | ✅ Yes | ✅ Yes |
| **Active drying** | ❌ No heater | ❌ No heater | ✅ Yes (45°C–85°C) |
| **MQTT humidity reporting** | Not exported | Exported (1–5) | Exported (%) |

**Source:** BambuStudio DevFilaSystem.cpp and GitHub issue #233 (vena/bambino) discussing AMS capabilities per type

#### 4. **G-Code Filament Change Integration**

When G-code is generated for multi-color prints, **M1020** is the Bambu-specific command for AMS slot selection:

```
M1020 S<slot_id> H<nozzle_id>
```

- `S` = slot ID in the AMS (0–3 for AMS Lite)
- `H` = nozzle ID (usually 0 for single-nozzle printers)

For external spool only (no AMS), the system uses **M600** (standard filament change pause).

**Source Files:**
- `.research/BambuStudio/src/libslic3r/GCode/GCodeProcessor.cpp` – M1020 processing (lines ~850–900)
- `.research/BambuStudio/src/libslic3r/GCode/GCodeWriter.cpp` – M1020 generation:
  ```cpp
  gcode << "M1020 S" << filament_id << " H" << nozzle_id;
  ```

#### 5. **Filament Mapping (AMS Mapping Array)**

Print jobs include an `ams_mapping` array in the MQTT print command that maps project colors to AMS slots:

```json
{
  "print": {
    "ams_mapping": [-1, -1, -1, 1, 0],
    ...
  }
}
```

**Mapping rules:**
- 5-element array (supports max 4 colors + padding)
- Array positions correspond to color indices in the project
- Array values are slot IDs (0–3) or –1 for unmapped
- Right-to-left assignment: colors fill from the end

**Example:** `[-1, -1, -1, 1, 0]` = 2 colors mapped to slots 1 and 0

**Source:** 
- `.research/BambuStudio/src/slic3r/Utils/CalibUtils.cpp` – AMS mapping construction
- OpenBambuAPI MQTT documentation

#### 6. **MQTT Filament Setting Command**

To change filament configuration in an AMS Lite slot (color, type, temps):

```json
{
  "print": {
    "command": "ams_filament_setting",
    "ams_id": 0,
    "tray_id": 0,
    "tray_color": "FF0000FF",
    "nozzle_temp_min": 210,
    "nozzle_temp_max": 240,
    "tray_type": "PLA"
  }
}
```

**Source:** `.research/BambuStudio/src/slic3r/GUI/DeviceManager.cpp` – `command_ams_filament_settings()` implementation

#### 7. **Firmware Type Switching**

BambuStudio can switch between AMS types (DC, AMS Lite, full AMS) via the **DevAmsSystemFirmwareSwitch** class:

- `IDX_DC = -1` – Direct connect / no AMS
- `IDX_LITE = 0` – AMS Lite firmware mode
- `IDX_AMS_AMS2_AMSHT = 1` – Full AMS/AMS2/AMSHT firmware mode

**Source:** `.research/BambuStudio/src/slic3r/GUI/DeviceCore/DevFilaAmsSetting.h` (lines 41–46)

### What a Native Reimplementation Needs

To replicate AMS Lite support in a native slicer/printer control system:

1. **Data Model**
   - Define a slot container with 4 `DevAmsTray` objects (each with filament metadata)
   - Track `DevAmsType = AMS_LITE (enum value 2)`
   - Parse MQTT `tray_exist_bits` to detect slot occupancy
   - Store filament: color (RRGGBBAA hex), type, weight, temps, RFID tag

2. **MQTT State Reception**
   - Parse `print.ams[i].ams[j]` array for unit and slot state
   - Extract `tray[]` array with current filament in each slot
   - Cache `tray_now` to track active slot
   - Decode `tray_exist_bits` bitmap to know which slots are filled

3. **G-Code Hooks**
   - Insert M1020 commands at tool-change points in G-code
   - Map project colors → AMS slots via `ams_mapping` array construction
   - For slots without AMS Lite, fall back to M600 pause

4. **MQTT Commands**
   - `ams_filament_setting` to update slot metadata on device
   - Optional: `ams_get_rfid` to read RFID tag data from slots

5. **UI Mapping**
   - Display 4 slots with current filament color, type, remaining %
   - Allow drag-drop filament assignment from project colors to slots
   - Indicate AMS Lite type in UI (no humidity/temp/drying controls unlike full AMS)

### Simpler Feature Set vs. Full AMS

**What AMS Lite does NOT have:**
- ❌ Humidity monitoring (no sensor reporting)
- ❌ Temperature monitoring (passive only)
- ❌ Drying/heating capability (no heater)

**What can be skipped in native reimplementation:**
- Remote drying commands (`start_drying`)
- Humidity UI controls (gauge, presets)
- Thermal management (only cold filament)

This makes AMS Lite implementation simpler: core logic is slot selection + filament metadata, without the thermal/drying subsystems.

### Evidence: Concrete Source Locations

| Aspect | File | Lines | Key Code/Structure |
|--------|------|-------|-------------------|
| Slot data model | `DevFilaSystem.h` | 34–134 | `DevAmsTray`, `DevAms` classes |
| AMS type enum | `DevDefs.h` | ~54–62 | `AMS_LITE = 2` |
| Slot count logic | `DevFilaSystem.cpp` | ~219 | `GetSlotCount()` returns 4 for Lite |
| M1020 command | `GCodeProcessor.cpp` | ~850–900 | `process_M1020()` |
| AMS mapping | `CalibUtils.cpp` | ~task_ams_mapping | `task_ams_mapping = "..."` JSON |
| MQTT parsing | `DevFilaSystem.cpp` | ~598–700 | Type casting & tray iteration |
| Filament setting cmd | `DeviceManager.cpp` | ~command_ams_filament_settings | JSON construction for MQTT |

### Next Steps for Integration

1. **Reverse-engineer printer MQTT protocol** – confirm AMS Lite message structure vs. sample payloads
2. **Implement slot state cache** – maintain 4-slot array, update on `push_status`
3. **Generate ams_mapping array** – match print colors to device slots
4. **Emit M1020 in G-code** – at each color transition
5. **Test with real A1/A1M + AMS Lite** – confirm slot selection and filament load behavior
