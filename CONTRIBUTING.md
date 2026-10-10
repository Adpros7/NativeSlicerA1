# Contributing

## Before you start

Read `AGENTS.md` in full — it is the binding operating contract for this
repository (development priorities, minimal-code standards, reuse-first
policy for slicing/geometry code, testing and git discipline, safety
rules). Human contributors and AI agents follow the same rules.

Read `SPEC.md` for product requirements and `TODO.md` for the current
phase and next unblocked task before proposing new work — the roadmap is
sequential by design (see `TODO.md`'s phase ordering); out-of-order
feature work needs a reason, not just enthusiasm.

## Development priorities (from AGENTS.md, descending order)

Safety → Correctness → Reuse of proven implementations → Reliability →
Maintainability → Performance → Minimal code → Feature completeness →
Visual polish. When a PR trades off a higher priority for a lower one,
say so explicitly in the description.

## Setup

```sh
Scripts/build-libslic3r.sh   # one-time, builds the vendored slicing engine
swift build
swift test
```

## Before opening a PR

1. `swift build` and `swift test` pass locally.
2. New non-trivial logic has a test (see `AGENTS.md` §7/`TODO.md`'s
   completion rules — researched/implemented/tested/hardware-verified are
   distinct states, don't conflate them).
3. If you touched printer communication or G-code generation: read
   `AGENTS.md` §11 (Printer Safety) and `SECURITY.md`'s disclosure section
   first. These changes get extra scrutiny.
4. If you vendored or linked a new third-party component: add it to
   `THIRD_PARTY_LICENSES.md` with its exact license and verify
   compatibility with this project's AGPLv3 license before merging.
5. Update `TODO.md` status for any task your PR completes or advances —
   don't mark something done until it's actually verified per the
   criteria in `TODO.md`'s "Task Completion Rules" section.

## Code review

See `AGENTS.md` §8 (Git Discipline) and §16 (Agent Behavior) for the
standard this project holds reviews to: focused commits, no unrelated
changes bundled in, no claiming test/hardware verification that didn't
happen.

## Licensing of contributions

By contributing, you agree your contribution is licensed under this
project's AGPLv3 license (see `LICENSE`). Do not contribute code copied
from a source whose license is incompatible with AGPLv3 — check
`THIRD_PARTY_LICENSES.md` for already-cleared sources, or ask before
adding a new one.
