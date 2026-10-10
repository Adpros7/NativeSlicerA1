# Phase 0 Research Findings

Source checkouts live in `.research/` (gitignored, not committed): shallow
clones of `bambulab/BambuStudio` and `SoftFever/OrcaSlicer` default branches,
pulled 2026-10-10.

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

## Next steps (unblocked)

- P0-005/P0-006: Swift/C++ interop and Metal rendering investigation.
- P0-007-P0-010: A1 protocol/AMS Lite/MakerWorld/camera investigation (use
  BambuStudio's `slic3r/Utils/` networking code as primary source, since it's
  the authoritative first-party implementation).
