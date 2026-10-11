# Third-Party Licenses

This project links against `libslic3r` (BambuStudio's slicing core,
pinned `v02.08.04.61`) via `Scripts/build-libslic3r.sh` →
`vendor/BambuStudio/` (not committed; built locally/in CI). That checkout
in turn vendors or fetches the third-party components below.
**Verification status is marked per row** — this file was compiled by an
AI agent (see `AI_DISCLOSURE.md`) by reading source headers and build
scripts directly where marked "✅ checked", and from well-known public
licensing of the named upstream project where marked "📋 public record,
not re-verified against the exact vendored file" — the latter should be
independently confirmed before any commercial/closed distribution
decision, though note this project is **AGPLv3**
(see `LICENSE`, `RESEARCH.md` §P0-004), so copyleft components below are
compatible by construction; the main compatibility question is whether
any component below is *more* restrictive than AGPLv3 permits combining
(none identified as of this writing).

## Core engine (AGPLv3, drives this project's license choice)

| Component | License | Pinned | Verification |
|---|---|---|---|
| BambuStudio / `libslic3r` | AGPLv3 | `v02.08.04.61` (`f5e51a2`) | ✅ checked (`LICENSE` file in repo root) |

| BambuStudio calibration test models | AGPLv3 | `v02.08.04.61` (`f5e51a2`) | ✅ checked (`.research/BambuStudio/LICENSE`; exact unmodified asset paths and provenance in `Sources/NativeSlicerA1/Resources/Calibration/NOTICE.md`) |

## Vendored under `vendor/BambuStudio/src/` (bundled source, compiled by us)

| Component | License | Verification |
|---|---|---|
| admesh (STL I/O) | GPL-2.0-or-later | ✅ checked (`src/admesh/stl.h` header) |
| Clipper | Boost Software License 1.0 | ✅ checked (`src/clipper/clipper.hpp` header) |
| Clipper2 | Boost Software License 1.0 | ✅ checked (`src/clipper2/.../*.h` header) |
| semver | MIT | ✅ checked (source header) |
| nanosvg | zlib-style (permissive) | ✅ checked (source header, Mikko Mononen) |
| libigl | MPL-2.0 | ✅ checked (`igl_inline.h` header) |
| Eigen (vendored copy) | MPL2 | 📋 public record (BambuStudio vendors Eigen's standard MPL2 distribution; `COPYING.README` present but not re-read line-by-line) |
| qhull | Qhull license (permissive, BSD-style) | ✅ checked (`COPYING.txt` present) |
| miniz | MIT / public domain | ✅ checked (`LICENSE` present) |
| glu-libtess | SGI Free Software License B | 📋 public record |

## Fetched by `deps/` (CMake ExternalProject, built from source)

| Component | Pinned version | License | Verification |
|---|---|---|---|
| Boost | 1.84.0 | Boost Software License 1.0 | 📋 public record |
| CGAL | (bundled w/ GMPXX support) | GPL-3.0-or-later / LGPL-3.0-or-later (dual, component-dependent) | 📋 public record |
| OpenCASCADE (OCCT) | V7_6_0 | LGPL-2.1 with OCCT linking exception | 📋 public record |
| Assimp | (deps/Assimp) | BSD-3-Clause | 📋 public record |
| OpenCV | 4.6.0 | Apache License 2.0 | 📋 public record |
| TBB (oneTBB) | (deps/TBB) | Apache License 2.0 | 📋 public record |
| OpenVDB | patched fork of 8.2 | MPL-2.0 | 📋 public record |
| NLopt | 2.5.0 | LGPL-2.1-or-later / MIT (algorithm-dependent) | 📋 public record |
| FreeType | 2.12.1 | FreeType License (FTL, BSD-style) or GPLv2 (dual, FTL used by default) | 📋 public record |
| GMP | 6.2.1 | LGPL-3.0-or-later / GPL-2.0-or-later (dual) | 📋 public record |
| MPFR | 3.1.6 | LGPL-3.0-or-later | 📋 public record |
| libcurl | (deps/CURL) | curl license (MIT/X derivative) | 📋 public record |
| OpenSSL | (deps/OpenSSL) | Apache License 2.0 (OpenSSL ≥3.0) | 📋 public record |
| expat | (deps/Expat) | MIT | 📋 public record |
| libjpeg-turbo | 3.0.1 | BSD-3-Clause / zlib / IJG (mixed, permissive) | 📋 public record |
| libpng | (deps/PNG, opencv 3rdparty copy also present) | libpng license (permissive) | 📋 public record |
| zlib | system (macOS SDK `libz.tbd`) | zlib License | 📋 public record |
| zstd | 1.5.7 | BSD License (dual BSD/GPLv2, BSD used by default) | ✅ checked (`LICENSE` file in fetched source) |
| OpenMeshCraft + OpenMeshCraftBoolean | (deps/OpenMeshCraft, BambuStudio-authored wrapper) | GPL-3.0 | ✅ checked (`LICENSE` file in fetched source) |
| libnoise | (deps/libnoise) | LGPL-2.1 | ✅ checked (`COPYING.txt` in fetched source) |

## Swift package dependency

| Component | License | Verification |
|---|---|---|
| CocoaMQTT (`emqx/CocoaMQTT`) | MIT | 📋 public record (stated in upstream README) |

## Action items before any distribution decision

1. Independently re-verify every "📋 public record" row against the exact
   vendored file/version (licenses can change between versions).
2. Confirm CGAL's dual GPL/LGPL split doesn't trigger a GPL-3-only
   (non-AGPL-compatible) code path for the specific CGAL packages this
   project's `libslic3r_cgal` target actually uses.
