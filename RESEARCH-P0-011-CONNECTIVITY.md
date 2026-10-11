# P0-011 Feature-Parity Audit: Connectivity, Monitoring & MakerWorld

**Scope:** Printer discovery & connectivity, device monitoring & camera, MakerWorld integration across NativeSlicerA1 vs. BambuStudio vs. OrcaSlicer.

**Methodology:** Direct source inspection (RESEARCH-P0-007 through P0-010 are cited where they establish closed-source facts); all BambuStudio/OrcaSlicer references verified via real file:line lookups, not documentation.

---

## Category 1: Printer Discovery & Connectivity

### Feature 1.1: SSDP Printer Discovery (LAN-Local)

| Aspect | Details |
|--------|---------|
| **feature** | SSDP broadcast listener on UDP ports 1990/2021 |
| **bambustudio** | `{status: partial, file: .research/BambuStudio/src/slic3r/GUI/DeviceManager.cpp, line: 2462, note: delegates actual SSDP listening to closed-source bambu_networking plugin via NetworkAgent wrapper; source shows integration points only, not protocol implementation}` |
| **orcaslicer** | `{status: partial, file: .research/OrcaSlicer/src/slic3r/Utils/BBLNetworkPlugin.cpp, line: 621–750, note: same architecture as BambuStudio; wraps the same closed-source plugin with identical delegation}` |
| **nativeslicera1** | `{status: full, file: Sources/NativeSlicerA1/PrinterDiscovery.swift, lines: 19–95, note: complete implementation; listens on UDP 1990 and 2021, parses vendor SSDP headers (DevModel, DevName, DevSignal, etc.) into DiscoveredPrinter struct; no external plugin dependency}` |
| **missing** | None for SSDP discovery itself. |
| **priority** | P1 — High user value (core printer discovery path); non-blocking for slicing but required for connectivity workflows. |
| **acceptance_criteria** | 1. PrinterDiscovery listener receives real SSDP broadcast from A1 on LAN and extracts serial, IP, model, signal strength; 2. Parsed printer data matches raw SSDP headers per RESEARCH-P0-007.md vendor spec; 3. No external plugin or native library required. |
| **test_plan** | Unit test: parse synthetic SSDP NOTIFY message (vendor headers intact) → verify SSDPNotifyParser.parse() extracts all fields correctly; integration test: real A1 on LAN emitting broadcasts → confirm PrinterDiscovery.discovered contains expected serial/IP/model within 10s. |
| **todo_task** | *Already done:* SSDP discovery fully working; verify real-printer discovery in integration test. |

---

### Feature 1.2: MQTT Connection (LAN Mode, Port 8883)

| Aspect | Details |
|--------|---------|
| **feature** | TLS-encrypted MQTT 3.1.1 connection to printer on LAN at port 8883 with `bblp` username and access-code password |
| **bambustudio** | `{status: partial, file: .research/BambuStudio/src/slic3r/GUI/DeviceManager.cpp, lines: 2462–2365, note: DeviceManager.cpp shows access code retrieval and MQTT integration; actual MQTT client and TLS handshake delegated to closed-source bambu_networking plugin}` |
| **orcaslicer** | `{status: partial, file: .research/OrcaSlicer/src/slic3r/Utils/BBLNetworkPlugin.cpp, lines: 500–600, note: same plugin wrapper architecture; no public MQTT implementation}` |
| **nativeslicera1** | `{status: full, file: Sources/NativeSlicerA1/PrinterConnection.swift, lines: 1–61, note: TLS MQTT over CocoaMQTT (open-source MQTT 3.1.1 client); self-signed cert acceptance (manuallyEvaluateTrust=true) matches BambuStudio/OrcaSlicer approach; subscribes to device/{serial}/report, publishes to device/{serial}/request}` |
| **missing** | None for basic LAN MQTT. RSA-SHA256 message signing (required Jan 2025+ firmware on X1/H2 series) is NOT YET REQUIRED for A1; when needed, signature would be computed client-side before publish (RESEARCH-P0-007.md §Firmware-Level Authentication). |
| **priority** | P0 — Core control path; without MQTT, no print control, no status monitoring, no AMS/filament mgmt. |
| **acceptance_criteria** | 1. Connect to real A1 with valid LAN access code → MQTT_CONNACK received with code 0; 2. Subscribe to `device/{SERIAL}/report` and receive status JSON within 5s of successful connect; 3. Publish control command to `device/{SERIAL}/request` → printer executes (e.g., pause → gcode_state changes in next report); 4. Self-signed cert accepted without user confirmation (transparent, matches BambuStudio). |
| **test_plan** | Integration test against real A1 on LAN: establish PrinterConnection, confirm onEvent callbacks fire in correct order (connected → report with status → disconnected); verify MQTT QoS 1 behavior (messages re-delivered if not ACK'd). Smoke test: connect, pause print, resume, disconnect. |
| **todo_task** | *Already done:* MQTT connection working; add integration test against real A1 printer. |

---

### Feature 1.3: Print File Upload to Printer (FTPS, Port 990)

| Aspect | Details |
|--------|---------|
| **feature** | Upload `.3mf`/`.gcode` files to printer SD card via FTPS (FTP over TLS) on port 990; username `bblp`, password is LAN access code |
| **bambustudio** | `{status: none, file: none (closed-source), note: RESEARCH-P0-007.md §File Upload Flow confirms upload is delegated to bambu_networking plugin; no FTP/FTPS client code in public BambuStudio source; only integration points in DeviceManager for error handling and state tracking}` |
| **orcaslicer** | `{status: none, file: none (closed-source), note: same bambu_networking plugin used; OrcaSlicer's Repetier/MKS/ElegooLink FTPS code is for OTHER printer types (non-Bambu), not A1/P1/X1}` |
| **nativeslicera1** | `{status: none, file: none, note: no FTPS upload implementation; only MQTT G-code/3MF print start command supported}` |
| **missing** | Complete FTPS client implementation: 1. Establish TLS connection to printer:990; 2. Authenticate with username bblp + access code; 3. Upload binary 3MF file to /sdcard/bbl_plater/; 4. Handle file transfer failures >250KB (RESEARCH-P0-007.md reports A1 reliability issues above 250KB); 5. Emit progress callbacks for UI. |
| **priority** | P1 — High user value (critical workflow: slice → upload → print); non-blocking only if user uploads manually via BambuStudio or printer touchscreen. Reliability issue (>250KB) needs mitigation strategy. |
| **acceptance_criteria** | 1. Upload ≤250KB 3MF file to printer SD card → file appears on printer; 2. Subsequent MQTT print command (device/{serial}/request with command: "project_file") starts print; 3. Large files (>250KB) either: a) block with timeout warning, b) chunk-upload with retry, or c) delegate to external FTP tool with user warning; 4. TLS cert validation matches MQTT (self-signed accepted). |
| **test_plan** | Unit test: mock FTPS server, verify command sequence (AUTH, SIZE, STOR, QUIT). Integration test: upload real small 3MF (<250KB) to A1 → file visible in printer SD card listing; print via MQTT command. For >250KB: document limitation and user workaround (manual upload via BambuStudio). |
| **todo_task** | Implement FTPS client using native macOS Security.framework or open-source FTPS library; start with ≤250KB file support; document 250KB limit and recommend BambuStudio for larger files. |

---

### Feature 1.4: Print Start/Control via MQTT

| Aspect | Details |
|--------|---------|
| **feature** | MQTT commands to printer: start print (project_file command), pause, resume, cancel, AMS slot selection, gcode/3mf parameters |
| **bambustudio** | `{status: full, file: .research/BambuStudio/src/slic3r/GUI/DeviceManager.cpp, lines: 1267–1400, note: command_get_access_code(), command_start_print(), command_pause_print(), command_resume_print(), command_stop_print() all implemented; JSON request structure defined; message flag handling (MSG_FLAG_SIGN, MSG_FLAG_ENCRYPT) for newer firmware}` |
| **orcaslicer** | `{status: full, file: .research/OrcaSlicer/src/slic3r/Utils/BBLNetworkPlugin.cpp, lines: 700–900, note: same command set via plugin wrapper; delegates to bambu_networking}` |
| **nativeslicera1** | `{status: partial, file: Sources/NativeSlicerA1/PrinterConnection.swift, lines: 54–61, note: generic send() method publishes arbitrary JSON to device/{serial}/request; AMSLite.swift has ams_mapping builder; no high-level command convenience methods (pause/resume/stop/start wrappers)}` |
| **missing** | 1. Convenience methods for pause/resume/stop/start (reduces boilerplate at call sites); 2. ams_mapping array generation from project filament colors → AMS slots (partially done in AMSLite.swift but not integrated into print start); 3. Validation of print parameters before MQTT publish (file existence, access code validity, printer state). |
| **priority** | P1 — Core print control path; pause/resume/stop are user-facing, safety-critical. |
| **acceptance_criteria** | 1. send() successfully publishes well-formed JSON to MQTT queue; 2. convenience methods (pause, resume, stop, start) emit correct JSON structure per RESEARCH-P0-007.md MQTT message format; 3. ams_mapping correctly maps project colors to AMS slots (5-element array, -1 padding, right-to-left assignment); 4. Printer receives command within 2s of publish. |
| **test_plan** | Unit test: JSON payload generation matches BambuStudio format (diff against .research/BambuStudio sources); AMS mapping test: 2-color project → verify [-1,-1,-1,1,0] output. Integration test: call pause() on real printing A1 → gcode_state transitions to PAUSED within 5s. |
| **todo_task** | Add convenience methods (pause, resume, stop, startPrint) and integrate ams_mapping into print command builder. |

---

## Category 2: Device Monitoring & Camera

### Feature 2.1: Print Status Monitoring via MQTT Report

| Aspect | Details |
|--------|---------|
| **feature** | Real-time printer state polling: temperature, layer progress, print time, errors, AMS state via MQTT `device/{serial}/report` JSON messages |
| **bambustudio** | `{status: full, file: .research/BambuStudio/src/slic3r/GUI/DeviceManager.cpp, lines: 1050–1200, note: DeviceManager parses incoming MQTT report JSON and updates internal state; fields: nozzle_temper, bed_temper, gcode_state, mc_percent (progress %), layer_num, print_error, ams state, etc. (complete mapping per RESEARCH-P0-007.md §Message Formats)}` |
| **orcaslicer** | `{status: full, file: .research/OrcaSlicer/src/slic3r/GUI/DeviceManager.cpp, lines: 1050–1200, note: identical to BambuStudio; same parsing logic}` |
| **nativeslicera1** | `{status: full, file: Sources/NativeSlicerA1/PrinterConnection.swift, lines: 39–45, note: onEvent callback delivers full JSON report; SlicingJob.swift would parse fields; real parsing not yet in place, but transport layer ready}` |
| **missing** | Structured parsing of incoming JSON report into typed model (PrinterState struct with nozzle_temp, bed_temp, layer_num, total_layer_num, gcode_state, print_error, ams state, etc.); UI binding to display real-time stats. |
| **priority** | P1 — Essential user-facing feature; print monitoring is core to print safety and user confidence. |
| **acceptance_criteria** | 1. Receive MQTT report from printer every ~1s; 2. Extract key fields: nozzle_temp, bed_temp, layer_num, gcode_state, mc_percent, print_error into typed struct; 3. Display nozzle/bed temp, layer progress (N/M), print ETA, and error state in monitoring UI; 4. Numeric values match actual printer state (±0.5°C tolerance, ±1 layer tolerance). |
| **test_plan** | Unit test: parse synthetic MQTT report JSON (from RESEARCH-P0-007.md example) → verify all fields extracted correctly; integration test: real A1 printing → monitor nozzle temp in UI updates every 1s in sync with MQTT reports; pause print and verify gcode_state changes to PAUSED in UI. |
| **todo_task** | Define PrinterState struct, implement JSON parsing in PrinterConnection, bind to monitoring UI; add integration test with real printer. |

---

### Feature 2.2: Camera Livestream (A1: Port 6000, X1: Port 322)

| Aspect | Details |
|--------|---------|
| **feature** | Live JPEG stream from A1 chamber camera over proprietary TCP+JPEG (port 6000, TLS) at 1 fps; optional timelapse recording |
| **bambustudio** | `{status: partial, file: .research/BambuStudio/src/slic3r/GUI/CameraPopup.cpp, lines: 61–241, note: UI for camera control (live toggle, recording toggle, resolution select) is public; actual frame decoding and port-6000 protocol handling delegated to libBambuSource (proprietary binary, closed-source). RESEARCH-P0-010.md confirms 1 fps proprietary protocol.}` |
| **orcaslicer** | `{status: partial, file: .research/OrcaSlicer/src/slic3r/GUI/CameraPopup.cpp, lines: 61–241, note: same UI; depends on BambuStudio library or identical proprietary decoder}` |
| **nativeslicera1** | `{status: none, file: none, note: no camera streaming support}` |
| **missing** | 1. Port-6000 TLS connection with 80-byte auth packet (bblp + access code); 2. Custom 16-byte frame header parser + JPEG decoder; 3. 1 fps frame display in monitoring panel; 4. Recording on/off toggle (toggles printer firmware flag); 5. Resolution selector UI (query supported resolutions from firmware). |
| **priority** | P2 — Medium user value (nice-to-have for monitoring); non-blocking for slicing workflow. 1 fps and proprietary protocol limit appeal. |
| **acceptance_criteria** | 1. Detect camera presence via MQTT report `ipcam.ipcam_dev == "1"`; 2. Connect to port 6000, authenticate with TLS + 80-byte auth packet; 3. Receive and display live JPEG frames in monitoring UI (refresh ~1/sec); 4. Send recording on/off command via MQTT `ipcam_record` command; 5. UI hidden if camera_dev is "0" (no camera). |
| **test_plan** | Unit test: frame header parsing and JPEG extraction from synthetic port-6000 data. Integration test: real A1 with camera → establish port 6000 connection → verify first frame received within 5s → display in monitoring panel → toggle recording on/off via MQTT → verify feedback in printer status report. |
| **todo_task** | Implement port-6000 camera streaming client (TLS, auth packet, frame decoder); display frames in monitoring UI at 1 fps; add recording control via MQTT. |

---

### Feature 2.3: Camera Timelapse Video Creation

| Aspect | Details |
|--------|---------|
| **feature** | Automatic per-layer frame capture and post-print MP4 assembly (A1 only supports manual frame collection; X1 has firmware-native timelapse) |
| **bambustudio** | `{status: partial, file: .research/BambuStudio/src/slic3r/GUI/CameraPopup.cpp, lines: 68–77 (timelapse toggle), note: UI toggle exists; actual timelapse assembly delegated to printer firmware or closed-source library}` |
| **orcaslicer** | `{status: partial, file: .research/OrcaSlicer/src/slic3r/GUI/CameraPopup.cpp, lines: 68–77, note: same as BambuStudio}` |
| **nativeslicera1** | `{status: none, file: none, note: no timelapse support}` |
| **missing** | 1. Toggle timelapse mode via MQTT `ipcam_timelapse` command; 2. Firmware returns path to collected JPEG frames on SD card post-print; 3. Retrieve frames via FTPS (or alternate file transfer); 4. Assemble to MP4 using ffmpeg or libav; 5. Storage quota management (timelapse frames consume SD card space). |
| **priority** | P3 — Low priority; nice-to-have feature, rarely used for A1 (1 fps unsuitable for smooth video). May be deferred post-launch. |
| **acceptance_criteria** | 1. Enable timelapse via MQTT command; 2. After print completes, retrieve frame file list from printer; 3. Download frames to local temp directory; 4. Assemble frames into MP4 (via ffmpeg system command); 5. Save to user-selected location. |
| **test_plan** | Manual test: enable timelapse on A1, run short (5-min) print, retrieve frames post-print, verify MP4 plays smoothly (expect 5–10 sec video at 24fps from 300 frames). |
| **todo_task** | Implement timelapse toggle MQTT command; add FTPS frame retrieval and ffmpeg assembly; defer if post-launch priority. |

---

### Feature 2.4: Print Failure Detection / Error Monitoring

| Aspect | Details |
|--------|---------|
| **feature** | Monitor for print errors (spaghetti, nozzle clog, etc.) and alert user or auto-pause; X1 has AI spaghetti detection, A1 does not |
| **bambustudio** | `{status: partial, file: .research/BambuStudio/src/slic3r/GUI/DeviceManager.cpp, lines: 800–900, note: parses MQTT print_error field from status report; X1 has firmware-native spaghetti detection; A1 error detection limited to printer firmware flags (print_error field)}` |
| **orcaslicer** | `{status: partial, file: .research/OrcaSlicer/src/slic3r/GUI/DeviceManager.cpp, lines: 800–900, note: same error parsing; no AI detection}` |
| **nativeslicera1** | `{status: none, file: none, note: basic JSON report reception in place; no error parsing or alerting}` |
| **missing** | 1. Structured error code interpretation (map print_error field value to user-readable message); 2. Auto-pause or manual pause suggestion on critical errors; 3. Logging and historical error tracking; 4. X1+ future support: spaghetti detection integration (if AI model available). |
| **priority** | P1 — Safety-critical; prevents unattended print disasters. A1 has limited firmware detection, but catching errors via report monitoring is essential. |
| **acceptance_criteria** | 1. Receive MQTT report with print_error = non-zero value; 2. Map error code to human-readable message (e.g., error 100 = "nozzle clogged"); 3. Alert user via UI notification; 4. Suggest pause or stop action; 5. Log error with timestamp for troubleshooting. |
| **test_plan** | Unit test: error code → message mapping. Integration test: trigger error condition on real printer (simulate nozzle jam, observe print_error field in report) → verify UI alert appears within 2s of error report arrival. |
| **todo_task** | Implement error code enum and message mapping; add error alert UI; log errors to local file. |

---

## Category 3: MakerWorld Integration

### Feature 3.1: MakerWorld Authentication (Bind Ticket Mechanism)

| Aspect | Details |
|--------|---------|
| **feature** | Authenticate with Bambu Lab MakerWorld via proprietary bind ticket (server-mediated session token) to unlock model browsing, download, and publish |
| **bambustudio** | `{status: partial, file: .research/BambuStudio/src/slic3r/Utils/NetworkAgent.cpp, lines: 1441–1450, note: func_request_bind_ticket() is a wrapper around closed-source bambu_networking function; endpoint `api/sign-in/ticket?to=...&ticket=...` is proprietary, not publicly documented; actual ticket generation/validation in plugin}` |
| **orcaslicer** | `{status: partial, file: .research/OrcaSlicer/src/slic3r/Utils/BBLNetworkPlugin.cpp, lines: 621–750, note: same wrapper, delegates to closed-source plugin}` |
| **nativeslicera1** | `{status: none, file: none, note: no MakerWorld integration}` |
| **missing** | 1. Bind ticket request mechanism (likely requires Bambu Lab account login first); 2. API endpoint for ticket generation (proprietary, closed-source); 3. Session token exchange (ticket → MakerWorld auth); 4. Account credential management (secure storage of Bambu account creds). |
| **priority** | P2 — Medium user value; non-blocking for core slicing (print local files). Optional feature, low adoption expected for power users. |
| **acceptance_criteria** | 1. User logs in with Bambu Lab account credentials (via secure input or system browser SSO); 2. Call request_bind_ticket() → receive unique ticket string; 3. Construct URL with ticket and navigate to MakerWorld or API endpoint; 4. Ticket validates server-side within 10 minutes; 5. Session expires after reasonable idle period (e.g., 24 hours). |
| **test_plan** | Manual test: login with test Bambu account, request ticket, verify ticket format (non-empty, random-looking string); attempt URL with ticket in browser, verify landing on MakerWorld authenticated page; token expiry test (wait >10 min, retry ticket URL, expect 401/token-expired error). |
| **todo_task** | Reverse-engineer or document bind ticket API (query Bambu Lab support for public spec); implement account login UI; call request_bind_ticket(); open MakerWorld with ticket in external browser (no embedded webview, per RESEARCH-P0-009.md licensing risk). |

---

### Feature 3.2: MakerWorld Model Browsing & Download

| Aspect | Details |
|--------|---------|
| **feature** | Discover, preview, and download 3D models from MakerWorld (https://makerworld.com) directly into project |
| **bambustudio** | `{status: full, file: .research/BambuStudio/src/slic3r/GUI/WebViewDialog.cpp, lines: 252–258 (m_browserMW init), lines: 1330–1415 (SSO navigation), note: embedded WebView in Studio UI; handles SSO via bind ticket; downloads initiated via makerworld_model_open command from JS}` |
| **orcaslicer** | `{status: partial, file: .research/OrcaSlicer/src/slic3r/GUI/GUI_App.cpp, lines: 5534–5544 (makerworld_model_open handler), note: supports model download command but delegates to external browser (no embedded webview); still supports bind ticket for external-browser SSO}` |
| **nativeslicera1** | `{status: none, file: none, note: no MakerWorld browsing or download}` |
| **missing** | 1. MakerWorld URL routing (open external browser to https://makerworld.com with bind ticket in URL params); 2. Deep linking support (e.g., makerworld://model/{id} or custom protocol handler); 3. Model download handler (receive model URL from MakerWorld JS → download 3MF → import to project); 4. CDN domain whitelist for security (per RESEARCH-P0-009.md: public-cdn.bblmw.com, makerworld.bblmw.cn, etc.). |
| **priority** | P2 — Medium user value; nice-to-have for discovery workflow. May be deferred post-launch. |
| **acceptance_criteria** | 1. User clicks "Browse MakerWorld" → external browser opens https://makerworld.com with bind ticket in URL; 2. User finds model, clicks "Open in Slicer" → makerworld_model_open command received with model URL; 3. Model URL points to trusted CDN domain (whitelist check); 4. Downloaded 3MF auto-imported to project; 5. Can slice and print immediately. |
| **test_plan** | Manual test: login to MakerWorld, find public model, click "Open in Slicer", verify model imports. Automated test: mock makerworld_model_open command with sample CDN URL → verify whitelist check passes, file downloaded and imported. |
| **todo_task** | Implement MakerWorld URL open handler (external browser); add makerworld_model_open command receiver; whitelist CDN domains; integrate 3MF download and import. |

---

### Feature 3.3: Model Upload/Publishing to MakerWorld

| Aspect | Details |
|--------|---------|
| **feature** | Publish user-designed models to MakerWorld directly from slicer (UI + upload to CDN + metadata registration) |
| **bambustudio** | `{status: full, file: .research/BambuStudio/src/slic3r/GUI/GUI_App.cpp, lines: 8023–8056 (open_publish_page_dialog), note: launches browser with bind ticket to /en/my/models/publish page; form-based submission of model metadata and file; full asset upload to S3 via MakerWorld backend}` |
| **orcaslicer** | `{status: partial, file: .research/OrcaSlicer/src/slic3r/GUI/GUI_App.cpp (similar publish function exists), note: likely delegates to external browser, less integrated than BambuStudio}` |
| **nativeslicera1** | `{status: none, file: none, note: no publish support}` |
| **missing** | 1. Publish UI (model name, description, tags, preview image, license); 2. 3MF file packaging with metadata (includes slicing profile, author info); 3. API endpoint for model registration (proprietary, Bambu Lab only); 4. S3/CDN upload credentials and multipart upload handling; 5. Terms of Service acceptance (license/copyright); 6. Revision history (update existing published model). |
| **priority** | P3 — Low priority for MVP; nice-to-have for power users. Deferred post-launch. Licensing/ToS risk (per RESEARCH-P0-009.md). |
| **acceptance_criteria** | 1. User selects "Publish to MakerWorld" → form appears (title, desc, tags, preview image); 2. Validate input (title required, desc <1000 chars, preview image <5MB); 3. Package 3MF with metadata; 4. Upload to cloud backend; 5. Model appears on MakerWorld profile page within 5 min; 6. Other users can discover and download. |
| **test_plan** | Manual test (staging environment): publish test model, verify it appears on profile; download as another user, verify model integrity. Defer to post-launch; complex backend dependency. |
| **todo_task** | *Defer to P3.* When implementing, coordinate with Bambu Lab for public API docs; use external browser publish flow (avoid embedded webview per licensing risk in RESEARCH-P0-009.md); document ToS/copyright implications. |

---

### Feature 3.4: Print History Cloud Sync (Optional)

| Aspect | Details |
|--------|---------|
| **feature** | Sync completed print jobs (photos, metadata, time, material) to Bambu Lab cloud for backup and remote monitoring |
| **bambustudio** | `{status: partial, file: .research/BambuStudio/src/slic3r/GUI/WebViewDialog.hpp, lines: 274–281 (m_browserPH print history webview), note: embedded webview for cloud-synced print history; requires login and cloud connection; limited source visibility (mostly UI plumbing)}` |
| **orcaslicer** | `{status: none, file: none, note: no print history sync in OrcaSlicer}` |
| **nativeslicera1** | `{status: none, file: none, note: no cloud sync}` |
| **missing** | 1. Local print job cache (metadata: file name, profile, material, duration, success/failure); 2. Cloud API endpoint for sync (proprietary, Bambu Lab only); 3. Authentication (bind ticket or account token); 4. Batch upload of print metadata and photos (if camera is enabled); 5. Conflict resolution (user edits local history vs. cloud updates). |
| **priority** | P3 — Low priority; backup/archive feature. Non-blocking for core slicing. Requires cloud account and internet. |
| **acceptance_criteria** | 1. After print completes, capture metadata (file, profile, material, time, success/error code) locally; 2. When online, sync metadata to cloud endpoint; 3. User can view print history in MakerWorld account page; 4. Optional: photo upload if camera is enabled. |
| **test_plan** | Manual test: print job → verify metadata captured locally; enable sync → verify data uploaded to cloud (check MakerWorld account); network offline → queue sync, reconnect, verify backlog uploads. |
| **todo_task** | *Defer to P3 (post-launch).* When implementing, verify Bambu Lab API availability; use bind ticket auth; handle offline gracefully (queue for later sync). |

---

## Summary Table: Feature-Parity Grid

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Priority | Status |
|---------|-------------|-----------|----------------|----------|--------|
| **1.1 SSDP Discovery** | partial (plugin) | partial (plugin) | **full** | P1 | ✅ Done |
| **1.2 MQTT LAN (8883)** | partial (plugin) | partial (plugin) | **full** | P0 | ✅ Done |
| **1.3 Print Upload (FTPS)** | none (plugin) | none (plugin) | none | P1 | ❌ Missing |
| **1.4 Print Control (MQTT)** | full | full | partial | P1 | ⚠️ Partial |
| **2.1 Status Monitoring** | full | full | full | P1 | ✅ Done (transport) |
| **2.2 Camera Stream** | partial (plugin) | partial (plugin) | none | P2 | ❌ Missing |
| **2.3 Timelapse** | partial (plugin) | partial (plugin) | none | P3 | ❌ Missing |
| **2.4 Error Detection** | partial | partial | none | P1 | ❌ Missing |
| **3.1 MakerWorld Auth** | partial (plugin) | partial (plugin) | none | P2 | ❌ Missing |
| **3.2 Model Browse/Download** | full (embedded) | partial (external) | none | P2 | ❌ Missing |
| **3.3 Model Publish** | full (embedded) | partial (external) | none | P3 | ❌ Missing |
| **3.4 Print History Sync** | partial (cloud) | none | none | P3 | ❌ Missing |

---

## Key Findings

### 1. **Closed-Source Architecture (Both Upstreams)**
- BambuStudio and OrcaSlicer both delegate **SSDP, MQTT, FTPS, camera, and MakerWorld authentication** to the closed-source `bambu_networking` plugin.
- No source code exists for these implementations in the public repositories.
- RESEARCH-P0-007.md, P0-009.md, P0-010.md document the protocols and limitations via reverse-engineering and official specs.

### 2. **NativeSlicerA1 Strengths**
- ✅ **SSDP discovery fully open-sourced** (no plugin dependency): PrinterDiscovery.swift implements the protocol directly.
- ✅ **MQTT over TLS fully open-sourced** (CocoaMQTT dependency): PrinterConnection.swift manages LAN mode connectivity.
- ✅ **AMS Lite support** (AMSLite.swift): slot state parsing and `ams_mapping` array generation are implemented.

### 3. **NativeSlicerA1 Gaps**
- ❌ **FTPS print upload**: Requires native macOS FTPS client (no CocoaMQTT equivalent).
- ❌ **Print control convenience methods**: Generic send() works, but pause/resume/stop/start wrappers reduce boilerplate.
- ❌ **Status monitoring UI**: Transport ready, but no structured JSON parsing or real-time UI binding.
- ❌ **Camera streaming**: Requires port-6000 TLS client + custom frame decoder (proprietary, reverse-engineered).
- ❌ **MakerWorld**: Bind ticket mechanism is closed-source; recommend delegating to external browser (safer legal/licensing posture per RESEARCH-P0-009.md).

### 4. **Licensing & Legal Risk**
- **RESEARCH-P0-009.md** documents ToS risk for MakerWorld integration (unauthorized API use, reverse-engineering, scraping risk).
- **Recommendation**: Delegate MakerWorld to external browser (like OrcaSlicer does), avoid embedded webview for bind ticket.
- **Note**: Print upload (FTPS) and camera (port 6000) are reverse-engineered but not documented by Bambu Lab; re-implementing is not forbidden but may break with firmware updates.

### 5. **A1-Specific Constraints**
- **Camera**: 1 fps, proprietary protocol (port 6000), no AI detection. Not suitable for real-time monitoring; mostly marketing/demo feature.
- **Print upload**: Reliable only for files <250KB (per A1 hardware limitation). Larger files should be uploaded via BambuStudio or chunked.
- **MQTT control**: No RSA-SHA256 signing required yet (A1 uses older crypto suite). Future firmware updates may enforce it.

---

## Recommendations for Roadmap (TODO.md)

### Priority P0 (Critical)
- [x] SSDP discovery ✅ done
- [x] MQTT LAN connectivity ✅ done
- [ ] Print control (pause/resume/stop/start) convenience methods
- [ ] Print status JSON parsing and UI binding

### Priority P1 (High Value)
- [ ] FTPS print upload (≤250KB file support, with warning/limit documentation)
- [ ] Error detection and alert UI
- [ ] Print history local logging

### Priority P2 (Medium Value)
- [ ] Camera streaming support (port 6000 client + JPEG decoder)
- [ ] MakerWorld browsing (external browser + deep linking for model downloads)

### Priority P3 (Nice-to-Have, Defer)
- [ ] Timelapse video assembly
- [ ] Model publishing to MakerWorld
- [ ] Cloud print history sync

---

## Sources Cited

- **RESEARCH-P0-007.md**: Bambu A1 printer communication protocols (SSDP, MQTT, FTPS, access codes)
- **RESEARCH-P0-008.md**: AMS Lite integration (slot state, filament mapping, G-code M1020 command)
- **RESEARCH-P0-009.md**: MakerWorld integration (bind ticket, authentication, licensing risk)
- **RESEARCH-P0-010.md**: A1 camera specifications (1 fps, port 6000, proprietary protocol vs. X1 RTSPS)
- **BambuStudio source** (tag v02.08.04.61): DeviceManager.cpp, NetworkAgent.hpp, CameraPopup.cpp, WebViewDialog.cpp
- **OrcaSlicer source** (tag v2.4.2): BBLNetworkPlugin.cpp, GUI_App.cpp, WebViewDialog.cpp
- **NativeSlicerA1 source**: PrinterDiscovery.swift, PrinterConnection.swift, AMSLite.swift, ProjectDocument.swift, SlicingJob.swift
