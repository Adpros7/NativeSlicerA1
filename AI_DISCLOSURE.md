# AI-Assisted Development Disclosure

This project is developed with substantial assistance from AI coding
agents (Claude, operating under the instructions in `AGENTS.md`),
alongside human review and direction.

## What this means in practice

- Code, documentation, and research findings in this repository may have
  been authored or drafted by an AI agent, then reviewed/accepted by a
  human maintainer via commit.
- Research documents (`RESEARCH.md`, `RESEARCH-P0-*.md`) are AI-produced
  source audits. They cite concrete file paths and line numbers where
  possible, but — per the explicit correction tracked in
  `TODO.md` P0-011 — not every claim has been independently re-verified
  by a human against the cited source. Treat them as a strong starting
  point, not a certified audit, until a feature/row is marked verified.
- Hardware-interaction code (printer communication, G-code generation) is
  explicitly marked **not hardware-verified** in `TODO.md` until tested
  against a physical Bambu Lab A1. No AI agent working on this project
  has access to physical printer hardware.
- Commit messages and `TODO.md`/`SESSION.md` status entries written by an
  AI agent follow `AGENTS.md`'s non-negotiable rules: no fabricated test
  results, no fabricated benchmarks, no claiming hardware verification
  without actual hardware access.

## Why disclose this

Transparency about AI involvement matters especially here because this
project:
- Controls physical hardware (3D printers) where incorrect G-code or
  unsafe printer commands have real-world consequences.
- Reuses AGPLv3-licensed upstream code (`libslic3r`/BambuStudio) — license
  compliance work (`THIRD_PARTY_LICENSES.md`) has been AI-drafted and
  should be independently verified before any commercial distribution.

## Verification trail

Every commit in this repository's history is attributable and reviewable
via normal Git tooling. `SESSION.md` records what was verified (tests run,
builds completed) versus what remains to be verified, per session.
