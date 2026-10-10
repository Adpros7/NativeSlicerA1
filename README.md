# NativeSlicerA1

A native macOS 3D slicer built with SwiftUI and Metal, optimized for the
Bambu Lab A1 and AMS Lite. See [SPEC.md](SPEC.md) for the full requirements
and [TODO.md](TODO.md) for current development status.

## Status

Early development (Phase 1 of 9 — see TODO.md). Not yet usable for
production printing. No feature has been validated against physical
hardware; treat everything printer-facing as unverified until TODO.md says
otherwise.

## License

AGPLv3 (see [LICENSE](LICENSE)). This project reuses `libslic3r`, the
slicing core from [BambuStudio](https://github.com/bambulab/BambuStudio)
(itself AGPLv3), which drives the license choice — see
[RESEARCH.md](RESEARCH.md) §P0-004 for the full rationale and
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for every vendored/linked
upstream component.

## Requirements

- macOS 14+, Xcode 15+ (Swift 5.10+ toolchain).
- [Homebrew](https://brew.sh) for build tooling (`cmake`, `ninja`).
- ~10GB free disk space and a one-time ~2-5 minute build for the vendored
  slicing engine (see below).

## Building

```sh
# One-time: builds the real libslic3r engine from BambuStudio source into
# vendor/ (gitignored). Idempotent — safe to re-run.
Scripts/build-libslic3r.sh

# Then the usual SwiftPM workflow:
swift build
swift test
swift run NativeSlicerA1
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for why the engine is integrated via
a C-ABI bridge rather than Swift's native C++ interop, and
[SESSION.md](SESSION.md) for the current implementation state and next
steps (updated each session per [AGENTS.md](AGENTS.md)).

## Documentation map

| File | Purpose |
|---|---|
| `SPEC.md` | Product requirements |
| `TODO.md` | Authoritative task tracker, phase-by-phase |
| `ARCHITECTURE.md` | Technical architecture decisions |
| `RESEARCH.md` + `RESEARCH-P0-*.md` | Upstream source/protocol research findings |
| `SESSION.md` | Session continuity state (resume point) |
| `AGENTS.md` | Rules for AI coding agents working in this repo |
| `AI_DISCLOSURE.md` | Disclosure of AI-assisted development |
| `SECURITY.md` | Vulnerability reporting, printer-safety disclosure |
| `CONTRIBUTING.md` | Contribution process |
| `THIRD_PARTY_LICENSES.md` | Every vendored/linked dependency and its license |

## Safety

This project controls physical 3D printer hardware. Generated G-code and
printer-control code paths are safety-critical — see `AGENTS.md` §11 and
`SECURITY.md` before contributing to those areas.
