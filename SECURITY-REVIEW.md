# Security Review (P8-002)

Scope: this repository's own Swift/C++ code and build scripts, per
`SECURITY.md`'s stated scope. Conducted as part of Phase 8 production
packaging. Every finding below cites the actual source location and was
checked by reading the real implementation, not inferred.

## Findings

### 1. TLS certificate verification disabled for printer connections — reviewed, accepted

`FTPSUploader.swift:88-93` and `CameraStreamClient.swift:98-103` both
install a `sec_protocol_options_set_verify_block` that unconditionally
calls `complete(true)`, accepting any TLS certificate without chain
validation.

**Assessment: intentional and correct for this threat model, not a
defect.** The Bambu A1's local-network MQTT/FTPS/camera services use a
self-signed certificate with no public CA — the same trust model every
Bambu-compatible tool (including BambuStudio itself) must accept to
function at all. `PrinterConnection`'s MQTT `didReceiveTrust` handler
already does the same (pre-existing, not touched this review). The real
security boundary for this class of device is the LAN access code
(a shared secret visible only on the printer's own screen) plus physical
network access, not the TLS certificate chain — standard for local IoT
device management apps. No change made.

### 2. FTP command injection via unsanitized remote filename — found and fixed

`FTPSUploader.upload(fileAt:remoteFileName:)` built the `STOR` command
line as `"STOR /sdcard/bbl_plater/\(remoteFileName)"` and sent it
directly over the plaintext-formatted (though TLS-wrapped) FTP control
channel. A `remoteFileName` containing CR/LF could inject additional FTP
commands; one containing `/` could escape the fixed upload directory.

Every current caller (`DeviceSessionModel.uploadGCode`/`startPrint`)
derives `remoteFileName` from `URL(fileURLWithPath:).lastPathComponent`
of an internally UUID-generated temp path, never raw user input — so
this was not reachable through the current UI. Fixed anyway at the one
function that formats the command (`FTPSUploader.swift`), rather than
relying on every future caller to sanitize first: rejects empty names
and any name containing `\r`, `\n`, or `/` before connecting.

**Bug found while writing the regression test, not just the fix:** the
first version of this guard compared `Character`s (`remoteFileName
.contains(where: { $0 == "\r" || … })`), which Swift's grapheme-cluster
`String` semantics silently defeats — `"\r\n"` (the exact CRLF
injection byte sequence) collapses into **one** `Character`, which never
equals `"\r"` or `"\n"` individually, so the guard never fired for a
real CRLF payload and the test hung trying to actually connect to a
closed port. Fixed by checking `.unicodeScalars` instead (`FTPSUploader
.swift`'s guard), which doesn't cluster CR+LF. This is itself evidence
for why a runnable regression test matters more than the fix alone —
`FTPSUploaderIntegrationTests
.testUploadRejectsInjectionCharactersInRemoteFileName` pins both the
original vulnerability and this specific bypass.

### 3. Keychain items syncable via iCloud Keychain — hardened

`KeychainStore.set` used `kSecAttrAccessibleAfterFirstUnlock`, which
(unlike its `…ThisDeviceOnly` variant) permits the item to sync to the
user's other Macs via iCloud Keychain. For third-party API
tokens/secrets (MyMiniFactory OAuth tokens/client secret), silent
cross-device propagation is an unnecessary blast-radius increase.
Changed to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
(`KeychainStore.swift`) — same unlock-gated accessibility, scoped to
this Mac only.

### 4. OAuth CSRF protection — reviewed, already correct

`MyMiniFactoryOAuth`'s authorization-code flow (`MyMiniFactoryAuth.swift`,
`MyMiniFactoryClient.swift`) generates a random `state` per sign-in
attempt and validates it against the callback (`authorizationCode(from
:expectedState:)` — `MyMiniFactoryClient.swift:231-236`). No change
needed.

### 5. Credential/secret logging — reviewed, no findings

Searched every `print`/`BOOST_LOG_TRIVIAL`/`os_log`-adjacent call site in
`Sources/NativeSlicerA1` for LAN access codes, OAuth tokens, or API
keys. None found logged; `PrinterConnection`/`FTPSUploader`/
`MyMiniFactoryClient` pass credentials directly into the relevant
API/Keychain call without an intermediate logged representation.

### 6. Hardcoded secrets — reviewed, no findings

No API keys, client secrets, or printer credentials are hardcoded in
source. `MyMiniFactoryAccount`'s `apiKey`/`clientID`/`clientSecret` are
user-entered at runtime (`MyMiniFactoryView.swift`) and persisted only
via `KeychainStore` (finding #3 above hardens this further).

## Code signing / packaging (P8-006/P8-007, cross-referenced here since security-relevant)

- `Scripts/package-app.sh` enables Hardened Runtime (`codesign --options
  runtime`) and a minimal entitlements set (`Resources/
  NativeSlicerA1.entitlements`) — `network.client`/`network.server`
  only (the latter for `PrinterDiscovery`'s real inbound SSDP multicast
  listener), no broader entitlement.
- App Sandbox is deliberately not enabled — see the entitlements file's
  own comment for the reasoning (direct distribution, not App Store;
  sandboxing vendored static C++ libraries + arbitrary user file I/O is
  a separate, much larger review out of proportion to this task).
- Every linked dynamic dependency is a macOS system path (`/usr/lib`,
  `/System/Library`) — `Scripts/package-app.sh` asserts this with an
  `otool -L` gate and fails the build otherwise (P9-007's from-source
  dependency build is what makes this possible). No third-party dylib
  supply-chain surface to audit at the packaged-app level.
- **Not notarized**: this environment has only an "Apple Development"
  signing identity (free, tied to an Apple ID), not a paid Apple
  Developer Program "Developer ID Application" certificate. `codesign`/
  `spctl --assess` output in this review session confirms the packaged
  `.app` is correctly signed+hardened-runtime but Gatekeeper rejects it
  (`spctl --assess` → `rejected`) on a second machine until notarized —
  an honest, real, unremovable blocker given available credentials, not
  a gap glossed over.

## Out of scope for this review (per `SECURITY.md`)

Vendored `libslic3r`/BambuStudio source, OpenCascade/TBB/Boost/etc.
third-party dependencies, and the printer's own firmware/cloud services
are explicitly out of scope — reported upstream, not audited here.
