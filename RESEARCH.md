# Phase 0 Research Findings

Source checkouts live in `.research/` and `vendor/BambuStudio` (gitignored,
not committed; `vendor/BambuStudio` is a symlink to the same checkout used
by `Scripts/build-libslic3r.sh`).

**Pinned versions (verified via GitHub releases/tags API, not assumed from
default branch — initial audit mistakenly used arbitrary `master`/`main`
HEAD commits, corrected below):**

| Project | Repo | Pinned tag | Commit | Tagged |
|---|---|---|---|---|
| BambuStudio | `bambulab/BambuStudio` | `v02.08.04.61` | `f5e51a20bd328d4a043af9344825d7347270c2c9` | 2026-09-29 |
| OrcaSlicer | `OrcaSlicer/OrcaSlicer` (moved from `SoftFever/OrcaSlicer`) | `v2.4.2` | `8500fcdccaa10b5099ac20d252af3a7c560046f1` | 2026-07-06 |

Note: `bambulab/BambuStudio`'s GitHub "latest release" marker pointed to
`v02.08.02.61`, which is *not* the newest tag — `v02.08.04.61` is newer but
apparently unmarked as "latest" in the GitHub UI. Used the newest tag by
version-sort, not the "latest release" marker, since the former is the more
reliable signal of the actual current stable line.


## P0-001 / P0-002: Source audit

Both projects share the same architecture, forked from PrusaSlicer/Slic3r:

- `src/libslic3r/` — pure C++ slicing core. No GUI toolkit dependency inside
  this directory (confirmed: no wx/GTK includes in `libslic3r/*.cpp`).
  ~124k LOC (BambuStudio), ~141k LOC (OrcaSlicer, superset with more
  calibration/multi-material tooling). Builds as a standalone static lib via
  CMake.
- `src/slic3r/GUI/` — wxWidgets desktop UI. Tightly coupled to wxWidgets;
  not portable to SwiftUI/Metal without a full rewrite. Not reusable as-is.
- `src/slic3r/Utils/` — printer communication, HTTP/FTP clients (relevant to
  P2-002/P2-003/P2-004, Bambu Studio's is the one with native AMS/A1 protocol
  knowledge; Orca forks the same code with community reverse-engineering
  fixes).
- Bundled third-party libs under `src/` (admesh, clipper/clipper2, earcut,
  qhull, libigl, libnest2d, Arachne wall generator, eigen, nlohmann-json,
  mcut, tinybvh) — each under its own permissive license (MIT/BSD/BSL),
  vendored as source. These are reusable independent of the AGPL core.

## P0-003: Reusable components identified

| Component | Location | Reuse plan |
|---|---|---|
| Slicing core (perimeters, infill, supports, Arachne walls, G-code export) | `libslic3r/` | Build as static/dynamic lib, call from Swift via C API shim. |
| Printer/AMS communication, A1 LAN protocol, MQTT/FTP client | `slic3r/Utils/` (BambuStudio fork specifically — has native Bambu protocol, Orca reverse-engineered for A1/non-X1 behavior gaps) | Port networking logic, not UI. Cross-check both forks for protocol divergence. |
| 3MF/STL/AMF import-export | `libslic3r/Format/` | Reuse directly. |
| Calibration G-code generators | `libslic3r/Calib.*`, Orca's calibration presets | Reuse presets/logic, build native UI. |
| Printer profiles (A1/A1 mini, AMS Lite) | `resources/profiles/BBL` (BambuStudio) | Reuse data files directly (config, not code — not GPL-encumbered as data, but verify per P0-004). |
| wxWidgets GUI | `slic3r/GUI/` | NOT reusable. SwiftUI/Metal replaces this entirely. |

## P0-004: License audit — CRITICAL CONSTRAINT

**Both BambuStudio and OrcaSlicer are licensed GNU AGPLv3** (`LICENSE` /
`LICENSE.txt`, confirmed by file header in both repos).

Implications for this project:

- AGPLv3 is copyleft. Linking against `libslic3r` (statically or dynamically,
  as a combined work) makes the **entire combined binary** subject to AGPLv3:
  source must be made available to any user who receives the binary
  (not just network users — the "network use" clause is an *addition* to
  GPLv3's copyleft, not a narrowing of it).
- This is incompatible with closed-source distribution (e.g. a paid Mac App
  Store app) unless either:
  1. The project is released as AGPLv3/GPLv3-compatible open source, or
  2. The slicing engine is reimplemented independently (defeats "reuse
     proven implementations" priority and is explicitly discouraged by
     AGENTS.md section 4), or
  3. A commercial relicense is obtained from Bambu Lab / OrcaSlicer
     maintainers (unlikely for Orca, a community project with many
     contributors — no single relicensing authority).
- Bundled third-party deps (admesh, clipper, earcut, etc.) are independently
  MIT/BSD/BSL licensed and are NOT a constraint by themselves — the
  constraint is `libslic3r`'s own AGPLv3 license as a derivative of Slic3r.
- Printer profile data files (`resources/profiles/`) are distributed under
  the same repo license; treat as AGPLv3-covered unless a separate data
  license is declared (none found in `resources/profiles/BBL`).

**Decision needed from project owner before Phase 1 begins:** this
repository (NativeSlicerA1) must itself be licensed AGPLv3 (or GPLv3, which
is compatible as a strict subset of obligations when not run as a network
service) if `libslic3r` is reused per AGENTS.md section 4. No code has been
written yet, so this is still a zero-cost decision point. Proceeding under
the assumption of **AGPLv3 for this repository** unless told otherwise, since
"reuse proven implementations" outranks "feature completeness" per AGENTS.md
section 2, and reimplementing a slicing engine from scratch is explicitly
out of scope.

## P0-007..P0-011: Detailed findings (see dedicated files)

Swift/C++ interop and Metal rendering (P0-005/P0-006) are resolved in
ARCHITECTURE.md. Remaining Phase 0 investigations, each in its own file
(evidence-cited against `.research/` checkouts):

- **RESEARCH-P0-007.md** — A1 printer communication: mDNS/Bonjour discovery,
  MQTT over TLS (port 8883) for control/telemetry, FTPS (port 990) for file
  upload, LAN-mode access-code auth, JSON message schema, A1-specific
  firmware/feature gating vs X1.
- **RESEARCH-P0-008.md** — AMS Lite: 4-slot `DevAmsType::AMS_LITE`, no
  heater/humidity/drying (passive, unlike full AMS), `M1020` G-code slot
  selection, `ams_mapping` project-color-to-slot array, MQTT state via
  `tray_exist_bits` / `ams[].tray[]`.
- **RESEARCH-P0-009.md** — MakerWorld: proprietary bind-ticket auth (not
  OAuth), embedded webview in BambuStudio vs external-browser handoff in
  OrcaSlicer (which dropped the embedded SSO UI). Undocumented API —
  reimplementation carries ToS risk; recommend OrcaSlicer's external-browser
  pattern over embedding Bambu's private endpoints.
- **RESEARCH-P0-010.md** — A1 camera: built-in, but proprietary
  `chamber_image` protocol on port 6000 (TLS+JPEG, **1 fps**, fixed focus),
  not RTSP like X1 (port 322, 30 fps, AI defect detection). No AI features
  available for A1 in either upstream project.
- **RESEARCH-P0-011.md** — Feature-parity matrix (25 categories) across
  BambuStudio/OrcaSlicer/this project's SPEC.md. Key gaps neither upstream
  covers, requiring original implementation: comprehensive connector system
  (SPEC wants 8+ types vs upstream's 3), automatic multi-plane model
  splitting, region-based multicolor scheduling, native macOS mesh repair
  (upstream uses Windows-only Netfabb API), G-code-to-3MF reconstruction.

## Status

Phase 0 research complete (P0-001 through P0-012). Remaining Phase 0 item:
P0-013 (build/test infrastructure), which is the entry point into Phase 1.

