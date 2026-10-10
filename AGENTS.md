# AGENTS.md

These instructions apply to every AI coding agent working in this repository.

Read this file and SPEC.md before making changes.

## 1. Primary Objective

Build the application described in SPEC.md.

Follow the implementation roadmap.

Maintain TODO.md as the authoritative task tracker.

Do not attempt to implement the entire application at once.

## 2. Development Priorities

In descending order:

1. Safety.
2. Correctness.
3. Reuse of proven implementations.
4. Reliability.
5. Maintainability.
6. Performance.
7. Minimal code.
8. Feature completeness.
9. Visual polish.

Do not sacrifice higher priorities to improve lower priorities.

## 3. Minimal Code Standards

Write the least amount of code necessary to implement the required functionality correctly.

Rules:

- Prefer simple solutions.
- Prefer standard libraries.
- Reuse existing implementations.
- Avoid unnecessary dependencies.
- Avoid unnecessary abstractions.
- Avoid speculative features.
- Avoid excessive boilerplate.
- Avoid duplicated logic.
- Avoid premature optimization.
- Avoid unnecessary configuration.
- Avoid custom frameworks.
- Avoid excessive comments.
- Avoid meaningless helper functions.
- Avoid broad refactoring.
- Avoid large unrelated changes.

Use clear names and straightforward control flow.

Prefer deleting unnecessary code over adding compatibility wrappers without justification.

Do not compress code into unreadable expressions merely to reduce line count.

## 4. Reuse Existing Slicer Code

Before implementing a slicing-related feature:

1. Search Bambu Studio.
2. Search OrcaSlicer.
3. Search existing project code.
4. Identify reusable implementations.
5. Check licenses.
6. Reuse or adapt existing code where appropriate.

Do not reimplement:

- Mature slicing algorithms.
- G-code generation.
- Geometry processing.
- Established calibration tools.
- Existing printer profiles.
- Existing connector algorithms.

unless there is a documented reason.

Keep upstream modifications isolated where practical.

Prefer thin interoperability layers over large rewrites.

## 5. Architecture

Use SwiftUI for native interfaces.

Use Metal for 3D rendering.

Use Swift Concurrency for asynchronous operations.

Reuse C++ slicing components.

Maintain clear boundaries between:

- UI.
- Application state.
- Geometry.
- Slicing.
- Optimization.
- Printer communication.
- Authentication.
- Persistence.
- Monitoring.

Avoid circular dependencies.

Do not introduce a new architectural pattern without a concrete need.

## 6. Task Management

Before coding:

1. Read TODO.md.
2. Check Git status.
3. Identify the next unblocked task.
4. Review relevant requirements.
5. Inspect existing implementations.
6. Define acceptance criteria.

Work on one coherent task at a time.

Update TODO.md as work progresses.

Do not mark tasks complete without verification.

## 7. Testing

Every meaningful implementation change requires relevant testing.

Use:

- Unit tests.
- Integration tests.
- Regression tests.
- Build verification.
- Static analysis where appropriate.

Safety-critical changes require additional validation.

Never claim tests passed unless they actually ran successfully.

Distinguish simulated validation from physical printer testing.

## 8. Git Discipline

Create a Git commit after every verified, coherent task.

Before committing:

1. Review the diff.
2. Remove accidental changes.
3. Run relevant tests.
4. Check for secrets.
5. Update documentation.
6. Update TODO.md.
7. Create a descriptive commit.

Never commit credentials.

Never commit unrelated changes.

Never rewrite unrelated Git history.

Do not force-push.

Do not create commits for incomplete or unverified functionality merely to show progress.

Use focused commit messages.

## 9. Documentation

Keep these files accurate:

- TODO.md
- ROADMAP.md
- ARCHITECTURE.md
- FEATURE_PARITY.md
- TESTING.md
- BENCHMARKS.md
- CHANGELOG.md

Document important architectural decisions.

Avoid documenting obvious code behavior unnecessarily.

Do not create redundant documentation.

## 10. Security

Never hardcode credentials.

Never log authentication tokens.

Use macOS Keychain.

Do not transmit private information to unauthorized services.

Use explicit permissions for sensitive functionality.

Do not bypass authentication protections.

Review dependencies before introducing them.

## 11. Printer Safety

Treat printer-control and G-code changes as safety-critical.

Never disable established safety checks.

Never assume generated toolpaths are collision-free.

Preserve validated printer procedures.

Experimental algorithms require validation.

Do not claim hardware verification without hardware testing.

## 12. Geometry Integrity

Preserve original models.

Use non-destructive operations.

Never automatically repair source meshes.

Mesh repair requires explicit user approval.

Connector generation must be reversible.

Unit conversion must be reversible.

Avoid unnecessary geometry modification.

## 13. Performance

Measure before optimizing.

Prefer algorithmic improvements over micro-optimizations.

Avoid unnecessary allocations.

Avoid blocking the main thread.

Use GPU acceleration when beneficial.

Do not introduce complex caching without demonstrated need.

Benchmark performance claims.

## 14. Error Handling

Handle expected failures explicitly.

Do not silently swallow errors.

Do not invent successful results.

Do not hide incomplete implementations.

Provide actionable errors.

Avoid unnecessary fallback chains.

Preserve a reliable conventional slicing path.

## 15. Dependencies

Prefer existing project dependencies.

Before adding a dependency, verify:

- Maintenance status.
- License.
- Platform compatibility.
- Security implications.
- Actual necessity.

Do not add dependencies for trivial functionality.

## 16. Agent Behavior

Do not repeatedly ask for approval for ordinary implementation decisions.

Make reasonable technical decisions within the specification.

Do not ask whether to proceed with the next planned task.

Proceed autonomously within the authorized development scope.

However, do not:

- Access credentials without required permission.
- Perform destructive operations without authorization.
- Bypass security protections.
- Claim unavailable hardware tests were performed.
- Publish releases or expose private data without authorization.

If blocked, document the blocker and continue with another independent task.

## 17. Session Start

At the beginning of each session:

1. Read AGENTS.md.
2. Read SPEC.md as needed.
3. Read TODO.md.
4. Inspect Git status.
5. Review recent commits.
6. Identify the next task.
7. Begin implementation.

Do not restart completed work.

## 18. Session End

Before ending:

1. Run relevant tests.
2. Review modifications.
3. Update TODO.md.
4. Update affected documentation.
5. Commit verified work.
6. Record blockers.
7. Identify the next task.

Leave the repository in a recoverable state.

## 19. Definition of Done

A task is complete only when:

- Code is implemented.
- The project builds.
- Relevant tests pass.
- Acceptance criteria are satisfied.
- Regressions are checked.
- Documentation is updated.
- Git changes are committed.

Hardware-dependent work additionally requires physical validation before being labeled hardware-verified.

## 20. Non-Negotiable Rules

- Never fabricate results.
- Never fabricate tests.
- Never fabricate feature parity.
- Never fabricate benchmarks.
- Never claim printer safety without appropriate validation.
- Never silently repair meshes.
- Never destructively modify source geometry.
- Never unnecessarily rewrite existing slicer functionality.
- Never implement the entire specification in one session.
- Never mark incomplete work complete.
- Never sacrifice safety for optimization.
- Never introduce unnecessary complexity.

Build the smallest correct solution, verify it, commit it, and proceed to the next task.

## Session Continuity and Automatic Resumption

Every development session must be independently resumable.

At the beginning of every session:

1. Read AGENTS.md, SPEC.md, and TODO.md.
2. Read ROADMAP.md and relevant architecture documentation.
3. Inspect Git status and recent commits.
4. Identify the current development phase.
5. Identify completed, incomplete, and blocked tasks.
6. Verify any work left unfinished by the previous session.
7. Select the next unblocked task.
8. Immediately resume development.

Do not depend on previous conversation history.

TODO.md and the Git repository are the authoritative sources of development progress.

Maintain a SESSION.md file containing:
- Current development phase.
- Last completed task.
- Current task and implementation progress.
- Important technical decisions.
- Uncommitted changes.
- Known blockers.
- Next recommended action.
- Relevant test commands.

Update SESSION.md after each completed task and before ending a session.

Never repeat completed work unless verification reveals a problem.

Never ask what to work on next when TODO.md already provides the answer.

Continue autonomously through the roadmap, implementing, testing, documenting, and committing verified tasks.

If the previous session ended unexpectedly, inspect the repository and recover the actual development state before continuing.