# Claude Code Instructions

This project is a native macOS 3D slicer for the Bambu Lab A1.

## Required Reading

Before starting any work, read:

1. AGENTS.md: Mandatory engineering rules.
2. SPEC.md: Complete product requirements.
3. TODO.md: Current tasks and progress.
4. ROADMAP.md: Development milestones, when available.
5. ARCHITECTURE.md: Technical decisions, when relevant.

Follow AGENTS.md for all development standards. Do not duplicate its instructions here.

## Workflow

1. Inspect Git status and recent commits.
2. Read TODO.md and identify the next unblocked task.
3. Search existing code and upstream slicers for reusable implementations.
4. Implement the smallest correct solution.
5. Build and run relevant tests.
6. Review changes for regressions and security issues.
7. Update TODO.md and relevant documentation.
8. Create a focused Git commit after verification.
9. Continue with the next unblocked task.

## Development Principles

- Reuse Bambu Studio and OrcaSlicer code wherever practical and legally permitted.
- Prefer minimal, readable, maintainable code.
- Use SwiftUI, Swift 6, and Metal where appropriate.
- Reuse established C++ slicing engines.
- Avoid unnecessary dependencies, abstractions, and boilerplate.
- Never rewrite proven functionality without justification.
- Never automatically repair or destructively modify source meshes.
- Never compromise printer safety.
- Never fabricate tests, benchmarks, or completion claims.

## Autonomous Execution

Work autonomously through TODO.md.

Do not ask for approval for routine implementation decisions.

Do not attempt to complete the entire specification in one session.

Break large tasks into independently verifiable subtasks.

If blocked, document the issue and continue with another independent task.

Preserve progress across sessions using repository documentation.

## Git

Commit after each verified, coherent task.

Use descriptive commit messages.

Never commit credentials, secrets, or unrelated changes.

Do not commit unverified functionality as complete.

## Session Completion

Before ending a session:

1. Run relevant tests.
2. Update TODO.md.
3. Update affected documentation.
4. Commit verified changes.
5. Record unresolved blockers.
6. Identify the next task.

Report completed tasks, tests, commits, blockers, and next steps concisely.

## Primary Rule

Build the smallest correct solution, verify it, commit it, and continue.