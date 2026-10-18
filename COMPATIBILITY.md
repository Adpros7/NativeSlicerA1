# Compatibility (P8-005)

Distinguishes software-verified functionality from hardware-dependent or
otherwise unverified claims, per AGENTS.md §11/§19/§20. "Verified" below
always means "exercised against the real, vendored engine and/or a real
protocol-level test fixture in this repository's automated suite" —
never "assumed to work."

## Platform

| Requirement | Value | Verified how |
|---|---|---|
| OS | macOS 14.0 (Sonoma) or later | `LSMinimumSystemVersion`/`Package.swift`'s `.macOS(.v14)`; built and run on macOS 27.0.1 this session. |
| Architecture | Apple Silicon (arm64) only | `vendor/BambuStudio` is built for `arm64` only (`Scripts/build-libslic3r.sh`'s `ARCH="arm64"`); no Intel (x86_64) build exists. Running on an Intel Mac is unsupported, not merely untested. |
| Dependencies | None beyond the OS | Every linked dylib/framework resolves to `/usr/lib` or `/System/Library` (verified via `otool -L`, gated in `Scripts/package-app.sh`) — no Homebrew/MacPorts runtime dependency. |

## Printer

Scoped to the **Bambu Lab A1** only (SPEC.md), not the broader Bambu
Lab fleet (A1 mini, P1P/P1S, X1/X1C, X2D, H2 series, etc.) — the
vendored profile closure (`Resources/Profiles/BBL`) includes only A1
machine/process/filament profiles.

| Capability | Status |
|---|---|
| Slicing (A1 machine/process/filament profiles) | **Software-verified.** Real `libslic3r` `Print::apply`/`validate`/`process`/`export_gcode`, `SlicingJobTests`. |
| Printer discovery (SSDP) | Implemented per RESEARCH-P0-007.md's reverse-engineered protocol; protocol-tested against a real captured packet format (`PrinterDiscoveryTests`). **Not hardware-verified** — no physical A1 in this environment. Live SSDP traffic WAS observed from a real network device during this session's GUI verification (Device tab discovered a live "N2S" — A1's real `model_id` — announcement); connecting/controlling it was deliberately not attempted without explicit hardware authorization, so this remains documented as live-discovery-observed, not control-verified. |
| LAN MQTT status/control | Protocol-tested against a real local TLS mosquitto broker (not a real printer) — `PrinterConnectionCommandTests`. **Not hardware-verified.** |
| FTPS upload | Protocol-tested against a real local TLS `NWListener` FTP server (exact command sequence, exact bytes) — `FTPSUploaderIntegrationTests`. **Not hardware-verified.** |
| Chamber camera snapshot | Byte-exact protocol-tested against a real local TLS server — `CameraStreamClientIntegrationTests`. **Not hardware-verified.** |
| AMS Lite mapping | Tested against RESEARCH-P0-008.md's documented examples. **Not hardware-verified** against a real AMS Lite unit. |
| "Start a new print" (project 3MF → upload → `project_file` MQTT command) | **Software-verified**: the project 3MF itself is proven correct (real `store_bbs_3mf` output, real zip contents, real embedded G-code — `ExportBBSProjectThreeMFTests`) and the upload+MQTT-command path is the same protocol-tested FTPS/MQTT code above. The complete round trip (a real A1 actually starting a print from it) is **not hardware-verified.** |

## Online model repositories

| Service | Status |
|---|---|
| MakerWorld | Browser handoff only (trusted-URL delegation), not an embedded integration — see TODO.md P5-001/P5-002 for why. |
| MyMiniFactory | Real OAuth2 + search/download client implemented and unit-tested against mocked transport + real Keychain. **Live API not verified in this environment** (Cloudflare challenge blocks the real API from this sandbox's network). |
| Thingiverse / Printables / Cults3D | Not integrated — see `RESEARCH-P5-MODEL-REPOSITORIES.md` for the per-service reasoning (Cloudflare-challenged, undocumented GraphQL, or no public download API, respectively). |

## File format compatibility

| Format | Direction | Status |
|---|---|---|
| STL (binary + ASCII) | Import/Export | Software-verified (real round-trip tests). |
| 3MF (plain/legacy format, `Format/3mf.cpp`) | Import/Export | Software-verified — this app's own project save/load format. |
| 3MF (Bambu project format with embedded G-code, `Format/bbs_3mf.cpp`) | **Export only** | Software-verified this session (`ExportBBSProjectThreeMFTests`) — real `store_bbs_3mf` output, inspected via actual zip extraction. Import of a Bambu-project-format 3MF (as opposed to this app's own plain-3MF projects) is not implemented. |
| G-code | Import (Preview only) / Export | Software-verified (`GCodeLoadTests`, real sliced output). |
| OBJ | Import/Export | Software-verified. |
| STEP | Import only | Software-verified (OpenCascade tessellation). |

## Known unsupported combinations

- Modifier-mesh objects (P4-013) are not yet threaded through the
  project-3MF export path (`ProjectDocument.exportProjectThreeMF` throws
  a clear error rather than silently dropping them) — same scope gap as
  the plain-G-code `slice()` path's `sliceToGCodeWithModifiers` special
  case.
- Multi-plate batch export to a single project 3MF exports only the
  *active* plate (matches the A1 being single-plate hardware).
