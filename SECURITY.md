# Security Policy

## Reporting a vulnerability

Open a [GitHub issue](https://github.com/Adpros7/NativeSlicerA1/issues)
marked `security`, or if the issue is sensitive (credential handling,
remote code execution, printer-control exploitation), open a private
[GitHub Security Advisory](https://github.com/Adpros7/NativeSlicerA1/security/advisories/new)
instead of a public issue.

Include: affected version/commit, reproduction steps, and impact
(what an attacker could do). We do not currently offer a bug bounty.

## Scope

In scope:
- This repository's own Swift/C++ code (`Sources/`, `Tests/`).
- Build scripts (`Scripts/`) and their effect on the local system.
- Credential storage (Keychain usage) and network communication with
  printers/cloud services implemented in this repo.

Out of scope (report upstream instead):
- Vulnerabilities in vendored upstream code
  (`libslic3r`/BambuStudio, OrcaSlicer, or any dependency listed in
  `THIRD_PARTY_LICENSES.md`) — report to the respective upstream project.
- Vulnerabilities in the printer's own firmware or Bambu Lab's cloud
  services — report to Bambu Lab.

## Printer-safety-critical disclosure

Per `AGENTS.md` §11 (Printer Safety), any report involving:
- G-code generation that could produce unsafe toolpaths or thermal
  commands,
- bypass of an existing safety check or validated printer procedure,
- credential leakage (LAN access codes, cloud tokens) that could let an
  attacker control a printer,

should be treated as **high severity** regardless of exploit complexity.
These are evaluated and fixed before any other open issue of equal or
lower severity.

## Handling

- Acknowledgement target: best-effort, no SLA at this project stage
  (pre-1.0, single/small maintainer team — see `TODO.md` for current
  phase).
- Fixes are released as a patch commit referencing the advisory; CVE
  requests are filed for confirmed, user-impacting vulnerabilities once
  the project has tagged releases.
- Credentials and printer access codes are never logged (see
  `AGENTS.md` §10); if you find a code path that logs them, report it as
  defined above.
