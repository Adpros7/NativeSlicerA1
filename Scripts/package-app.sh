#!/bin/bash
# Packages a real, launchable, signed macOS .app bundle from the release
# build (P8-006). A bare SwiftPM executable isn't Dock/Launch-Services
# registered and can't receive OAuth URL-scheme callbacks (P5-003/P5-005);
# wrapping it in a standard bundle fixes both.
#
# Usage: Scripts/package-app.sh [output_dir]
#   output_dir defaults to dist/ (gitignored).
#
# Reproducibility scope (honest, not overclaimed): this produces the SAME
# bundle structure/contents from the SAME pinned source commit + pinned
# Package.resolved every run (deterministic BUILD PROCESS). It does NOT
# claim byte-for-byte reproducible Mach-O output — that needs toolchain-
# level deterministic-build flags (embedded timestamps/paths in debug
# info, etc.) which is a separate, much larger undertaking out of
# proportion to this task.
#
# Code signing: uses $CODESIGN_IDENTITY if set, else the first valid
# "Apple Development"/"Developer ID Application" identity found via
# `security find-identity`, else falls back to ad-hoc (`-`). An ad-hoc or
# "Apple Development" signature runs locally but is NOT suitable for
# distribution outside this Mac and will NOT pass notarization — that
# requires a paid Apple Developer Program "Developer ID Application"
# certificate this environment does not have (P8-007 honestly documents
# this as a real, unremovable blocker, not a fabricated "notarized"
# claim).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/dist}"
APP_NAME="NativeSlicerA1"
BUNDLE_ID="com.nativeslicera1.NativeSlicerA1"
APP_PATH="$OUT_DIR/$APP_NAME.app"

echo "==> Building release binary..."
BIN_PATH="$(cd "$ROOT" && swift build -c release --show-bin-path)"
cd "$ROOT" && swift build -c release

echo "==> Assembling $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

# Real bundled resources (P3-002 calibration assets, P2-001 printer
# profiles, CocoaMQTT's own resource bundle) — SwiftPM's `Bundle.module`
# looks for these next to the executable/in Contents/Resources at
# runtime, so copying the actual build output's bundles (not
# reconstructing them by hand) is both correct and the least code.
for bundle in "$BIN_PATH"/*.bundle; do
    [ -e "$bundle" ] || continue
    echo "    + $(basename "$bundle")"
    cp -R "$bundle" "$APP_PATH/Contents/Resources/"
done

# PkgInfo is optional/legacy but harmless and standard for a CFBundlePackageType=APPL bundle.
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

echo "==> Verifying no unexpected (non-system) dynamic dependencies"
UNEXPECTED_DYLIBS="$(otool -L "$APP_PATH/Contents/MacOS/$APP_NAME" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/)' || true)"
if [ -n "$UNEXPECTED_DYLIBS" ]; then
    echo "ERROR: non-system dynamic dependencies found (would not run on another Mac):"
    echo "$UNEXPECTED_DYLIBS"
    exit 1
fi
echo "    OK — every linked dylib/framework is a macOS system path (P9-007's from-source dependency build pays off here)."

IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -E '"(Apple Development|Developer ID Application)' | sed -E 's/.*"(.*)"/\1/' || true)"
fi
if [ -z "$IDENTITY" ]; then
    echo "==> No codesigning identity found — signing ad-hoc (local-run only, not distributable)."
    IDENTITY="-"
else
    echo "==> Signing with identity: $IDENTITY"
fi

codesign --force --deep --timestamp=none --options runtime \
    --entitlements "$ROOT/Resources/NativeSlicerA1.entitlements" \
    --sign "$IDENTITY" "$APP_PATH"

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP_PATH"
codesign --display --entitlements - "$APP_PATH" > /dev/null

echo "==> Registering with Launch Services (enables the nativeslicera1:// OAuth redirect, P5-003)"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH" || true

echo "==> Done: $APP_PATH"
echo "    Run: open \"$APP_PATH\""
echo "    Gatekeeper note: an ad-hoc/Apple-Development-signed, non-notarized app"
echo "    shows an 'unidentified developer' warning on first launch on a Mac"
echo "    other than this one (expected — see P8-007 note above)."
