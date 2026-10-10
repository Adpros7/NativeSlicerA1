## P0-007: Bambu A1 Printer Communication Protocols

### Discovery Mechanism: SSDP (CORRECTED — see note)

> **Correction (verified 2026-10-10):** the original pass below cited
> `Bonjour.cpp` as the A1 discovery mechanism. Verified against source:
> `Bonjour(std::string service)` in that file is only ever constructed with
> `Bonjour("octoprint")` (`BonjourDialog.cpp:155`) — it's legacy upstream
> Slic3r's generic OctoPrint mDNS discovery, **unrelated to Bambu printers**.
> Bambu's actual LAN discovery/MQTT/FTPS implementation is delegated
> entirely to the closed-source `bambu_networking` plugin
> (`NetworkAgent.cpp` loads it as an external native library) — no source
> for it exists in this repo. The real protocol, below, comes from
> community reverse-engineering (Bambu Lab Printer Reverse-Engineering
> Knowledge Base, `ssdp-go`, `open-bamboo-networking`), not from reading
> BambuStudio source.

**Implementation Details:**
- **Protocol**: Non-standard SSDP (UPnP-derived), not mDNS/Bonjour.
- **Transport**: Printer broadcasts UDP from source port 1900 to
  destination ports **1990 and 2021** (not the standard SSDP port 1900 on
  the receive side — a deliberate Bambu deviation from the SSDP spec).
- **Message**: `NOTIFY * HTTP/1.1` with `NT: urn:bambulab-com:device:3dprinter:1`,
  `USN: <serial>`, `Location: <printer IP>`, plus vendor headers
  `DevModel.bambu.com`, `DevName.bambu.com`, `DevSignal.bambu.com` (RSSI),
  `DevConnect.bambu.com` (lan/cloud), `DevBind.bambu.com`, `DevVersion.bambu.com`.
- Printer repeats the broadcast every ~5 seconds; no query/response
  handshake needed, just listen.
- Does not cross VLANs/subnets (broadcast, not multicast) — community
  workarounds (e.g. `bambu-bridge`) relay it across subnets.

**A1-Specific Notes:**
- Same discovery mechanism as all Bambu LAN printers (A1, A1 mini, P1, X1).
- No official documentation; Bambu Lab forum thread acknowledges the
  non-standard port choice (`forum.bambulab.com/t/use-ssdp-standards/7173`).

---

### Transport Protocols & Ports

#### 1. MQTT (Messaging)
- **Port**: 8883 (TLS/SSL encrypted, NOT standard MQTT port 1883)
- **Protocol**: MQTT over TLS 1.2+
- **Connection Modes**:
  - **LAN Mode**: `<printer_ip>:8883` (local printer IP)
  - **Cloud Mode**: `us.mqtt.bambulab.com:8883` (cloud broker)
  
- **Topics**:
  - **Subscribe**: `device/{serial_number}/report` (status updates from printer)
  - **Publish**: `device/{serial_number}/request` (commands to printer)
  - Serial number is 15 digits (e.g., `01P00A392000494`)

#### 2. FTPS (File Transfer)
- **Port**: 990 (Implicit FTPS, TLS-wrapped FTP)
- **Protocol**: FTP with TLS 1.2+ encryption wrapping (NOT SFTP/SSH)
- **Use Case**: Upload `.3mf` files to printer SD card, retrieve timelapse videos, manage files
- **Limitations for A1**:
  - File transfer speed: ~250 KB/s
  - Reliability issues above 250 KB (frequent hangs/crashes)
  - Mainly used for deletion, not uploading
  - Note: FTPS does NOT require LAN mode enabled (unlike MQTT control)

#### 3. HTTP/HTTPS (Cloud API)
- **Port**: 443 (HTTPS)
- **Endpoint**: Bambu Lab cloud server
- **Use**: Cloud mode authentication, firmware updates, remote monitoring when LAN unavailable

---

### Authentication Scheme

#### Access Code (LAN Mode Shared Secret)
- **Username**: `bblp` (fixed literal string)
- **Password**: Access code displayed on printer LCD in Settings > Lan Only Mode
- **Generation**: Unique per-device, user-configurable
- **Transmission**: Over TLS 1.2+; plaintext only over encrypted channels
- **Source Code**: `.research/BambuStudio/src/slic3r/GUI/DeviceManager.cpp` lines 466–509
  - `get_access_code()` retrieves stored/cached access code
  - `set_access_code()` and `set_user_access_code()` manage credentials
  - App config storage: `wxGetApp().app_config->set_str("access_code", dev_id, code)`

#### Firmware-Level Authentication (January 2025+)

**RSA-SHA256 Message Signing (Newer Firmware)**:
- All MQTT commands require RSA-SHA256 signing with X.509 certificate
- **Certificate**: Public X.509 cert extracted from Bambu Connect desktop app (January 2025)
- **Affected Models**: X2D, H2D, H2S, H2C, P2S, X1E, refreshed P1/X1 firmware (Jan 2025+)
- **A1 Status**: **NOT yet required on A1/A1 mini firmware** (older crypto suite; supports AES-XTS, HMAC, RSA signatures, not full RSA-SHA256)
- **Signature Error Code**: 84033543 when unsigned commands sent to protected firmware
- **Impact**: Third-party tools (OrcaSlicer, Home Assistant integrations) must sign messages or fail

#### Cloud Mode Authentication
- **Method**: JWT-based access token
- **Username Format**: `u_{uid}` (derived from account token)
- **Scope**: Requires Bambu Lab cloud account login
- **Requires**: Internet connectivity

---

### Message Formats: JSON over MQTT

#### Status Report (Subscribe to `device/{serial}/report`)

```json
{
  "print": {
    "nozzle_temper": 23.625,
    "nozzle_target_temper": 0,
    "bed_temper": 20.71875,
    "bed_target_temper": 0,
    "chamber_temper": 5,
    "gcode_state": "IDLE|RUNNING|PAUSE|FAILED|FINISH",
    "mc_percent": 45,
    "mc_remaining_time": 3600,
    "layer_num": 125,
    "total_layer_num": 250,
    "print_error": 0,
    "lifecycle": "pre_print|printing|paused|finished",
    "wifi_signal": -40,
    "spoolman": null,
    "ams": { "ams_exist_bits": "0", "tray_now": "255", ... },
    "vt_tray": { ... },
    "fan_gear": 0,
    "nozzle_diameter": "0.4",
    "aux_part_temp": 0,
    "bed_type": "Auto",
    "subtask_id": "0",
    "subtask_name": "",
    "is_nozzle_clogged": false,
    ...
  }
}
```

#### Command Request (Publish to `device/{serial}/request`)

```json
{
  "print": {
    "command": "project_file",
    "url": "file:///sdcard/some_file.gcode.3mf",
    "param": "Metadata/plate_1.gcode",
    "subtask_id": "0",
    "use_ams": false,
    "timelapse": false,
    "flow_cali": false,
    "bed_leveling": true,
    "layer_inspect": true,
    "vibration_cali": false
  }
}
```

**Constraints**:
- Only `.3mf` files can be started (not `.gcode`); file must be on printer SD card
- JSON payloads must be normalized (key ordering, whitespace removal) to match Bambu Studio format for parsing
- Message signing required on Jan 2025+ firmware (not yet A1)

#### System Commands (Get Access Code)

```json
{
  "system": {
    "command": "get_access_code"
  }
}
```

Response received in status reports with sequence ID matching

---

### Firmware/Version Gating Differences: A1 vs X1

#### MQTT Control Restrictions (Firmware-Level Policy)

| Feature | X1/X1E/H2 | A1/A1 mini | Notes |
|---------|-----------|-----------|-------|
| **Cloud Mode MQTT Status** | Read-only (post-June 2023) | Read-only (post-June 2023) | Firmware update restricted printer control |
| **LAN Mode MQTT Control** | Full support | Full support with restrictions | A1 requires LAN mode explicitly enabled |
| **FTPS File Transfer** | Works in both modes | Works in both modes | Does NOT require LAN mode |
| **RSA-SHA256 Signing** | Required (Jan 2025+) | **NOT required** (older crypto) | A1 uses AES-XTS/HMAC/RSA; X1 uses AES/SHA/RSA |
| **Certificate Auth** | X.509 cert required | Not yet enforced | A1 firmware older, no cert validation |

#### Specific A1 Constraints

**LAN Mode Requirement for MQTT Control**:
- Source: `.research/BambuStudio/src/slic3r/GUI/DeviceManager.cpp` line 2462: `if (is_lan_mode_printer())`
- A1 control only functions when LAN mode enabled on printer
- Enabling LAN mode disables Bambu Cloud features until explicitly toggled back
- Downside: loss of remote monitoring, cloud backup during LAN mode

**Hardware Crypto Support**:
- X1/X1E: AES, SHA, RSA algorithms
- A1/A1 mini/P1: **AES-XTS, HMAC, RSA signatures** (subset, no SHA support)
- Implication: A1 cannot sign full RSA-SHA256 payloads; RSA-SHA256 firmware updates may not apply to A1

**Access Code UI Availability**:
- A1 mini limited touchscreen requires enabling LAN mode via Bambu Studio (not on printer LCD like P1/X1)
- Access code displayed after enabling LAN mode in Settings menu

---

### Code Architecture in BambuStudio

**Key Files**:
1. **Header**: `.research/BambuStudio/src/slic3r/Utils/bambu_networking.hpp` (488 lines)
   - Defines `PrintParams` struct, error codes, callback function types
   - `MSG_FLAG_SIGN` and `MSG_FLAG_ENCRYPT` flags for message signing/encryption
   - `BBL` namespace containing all networking definitions

2. **Device Manager**: `.research/BambuStudio/src/slic3r/GUI/DeviceManager.cpp`
   - Line 466–509: Access code management (`get_access_code`, `set_access_code`)
   - Line 1267: `command_get_access_code()` MQTT system command
   - Line 1275–1310: Access code refresh flow with callbacks
   - Line 2365: Password set to `get_access_code()` for MQTT connections
   - Line 2394, 2462: `is_lan_mode_printer()` guards for LAN-only features

3. **Bonjour Discovery**: `.research/BambuStudio/src/slic3r/Utils/Bonjour.cpp`
   - Custom mDNS/DNS-SD implementation (minimal, security-hardened)
   - RFC 6762/6763 compliant
   - Multicast UDP handling with robust parsing

4. **Network Agent Wrapper**: `.research/BambuStudio/src/slic3r/Utils/NetworkAgent.hpp/cpp`
   - Loads external native library (bambustudio_network_plugin)
   - Function pointers for MQTT, FTP, authentication, file transfer
   - Version 02.08.04.57 (from header)

5. **MQTT Integration**:
   - No source code for MQTT implementation in public C++ source (delegated to native library)
   - Callbacks registered via `set_on_message_fn`, `set_on_local_message_fn`
   - Message flags: `MSG_FLAG_SIGN` (1), `MSG_FLAG_ENCRYPT` (2) passed to `send_message_to_printer`

---

### A1-Specific Implementation Details

**LAN Mode Detection**:
```cpp
// DeviceManager.cpp
bool MachineObject::is_lan_mode_printer() const
```
- Returns true if printer currently in LAN-only mode
- Used to gate MQTT control, AMS sync, calibration features

**Access Code Flow**:
```cpp
// DeviceManager.cpp lines 1275–1310
std::string request_access_code(AccessCodeRefreshCallback callback)
{
  // Publishes: j["system"]["command"] = "get_access_code"
  // Printer responds in status report with access code
  // Callback fired with new code
}
```

**Network Plugin Loading**:
- `.research/BambuStudio/src/slic3r/Utils/NetworkAgent.cpp`
- Loads `bambu_networking.dll` (Windows) or `.so` (Linux) from plugins directory
- All actual MQTT, FTPS, and cloud operations delegated to compiled native library
- Wrapper maintains C++ ABI compatibility across versions

---

### File Upload Flow (FTPS)

**Usage**:
1. Gcode/3MF uploaded via FTPS:// (implicit TLS) to port 990
2. Credentials: username `bblp`, password = LAN access code
3. File placed in `/sdcard/bbl_plater/` directory
4. MQTT message sent to trigger print: `device/{serial}/request` with `url: file:///sdcard/...`

**Limitations (A1-Specific)**:
- Files >250 KB transfer slowly or hang
- Mainly used for deleting unwanted prints, not uploading
- Python FTPS libraries handle large files better than BambuStudio UI

---

### Error Handling

**MQTT-Related Error Codes** (from `bambu_networking.hpp`):
- `-1` to `-60`: General errors (connect, send, timeout, MD5 check)
- `-2010` to `-2140`: Print workflow (record, upload, FTP)
- `-3010` to `-3140`: Cloud print workflow
- `-4010` to `-4030`: Local print/SDCard workflow
- `-6010` to `-6020`: Connection failures (printer, server)

**Example**:
```cpp
#define BAMBU_NETWORK_ERR_TIMEOUT             -17
#define BAMBU_NETWORK_ERR_FTP_UPLOAD_FAILED   -20
#define BAMBU_NETWORK_ERR_PRINT_LP_UPLOAD_FTP_FAILED -4020
```

---

### Summary Table

| Aspect | A1/A1 mini | Source File |
|--------|-----------|------------|
| **Discovery** | mDNS/Bonjour _printer._tcp | Bonjour.cpp:24-806 |
| **MQTT Port** | 8883 (TLS) | bambu_networking.hpp:144-486 |
| **FTPS Port** | 990 (implicit TLS) | DeviceManager.cpp:447-449 |
| **MQTT Auth** | bblp + access_code | DeviceManager.cpp:466-509 |
| **FTPS Auth** | bblp + access_code | (same as MQTT) |
| **Message Format** | JSON (device/{serial}/report, request) | bambu_networking.hpp (callback types) |
| **LAN Mode Gating** | Required for MQTT control | DeviceManager.cpp:is_lan_mode_printer() |
| **Crypto Suite** | AES-XTS, HMAC, RSA (no SHA) | White paper (cited) |
| **RSA-SHA256 Required** | NO (not yet) | schwarztim/bambu-mcp, Hackaday article |
| **File Transfer Limit** | 250 KB+ unreliable | Forum discussion |

---

### References & Evidence

1. **BambuStudio Repository**: https://github.com/bambulab/BambuStudio (AGPLv3)
   - Bonjour implementation: `src/slic3r/Utils/Bonjour.cpp`
   - Device manager: `src/slic3r/GUI/DeviceManager.cpp`
   - Networking headers: `src/slic3r/Utils/bambu_networking.hpp`

2. **Community Documentation**:
   - MQTT for A1: https://forum.bambulab.com/t/mqtt-for-a1/50033
   - FTPS on A1: https://forum.bambulab.com/t/we-can-now-connect-to-ftp-on-the-p1-and-a1-series/6464
   - Bambu Lab Cloud API: https://github.com/coelacant1/Bambu-Lab-Cloud-API

3. **Security & Firmware**:
   - X.509 Certificate Extraction (Jan 2025): https://hackaday.com/2025/01/19/bambu-connects-authentication-x-509-certificate-and-private-key-extracted/
   - schwarztim/bambu-mcp (RSA-SHA256 implementation): https://github.com/schwarztim/bambu-mcp

4. **A1-Specific Hardware**:
   - Bambu Lab Security White Paper: X1 (AES/SHA/RSA) vs A1/P1 (AES-XTS/HMAC/RSA)
   - Forum discussions: A1 mini LAN mode UI, file transfer limitations

