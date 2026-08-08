#!/usr/bin/env bash
# sign-app.sh — codesign Signoff.app with Developer ID + Hardened Runtime.
#
# Usage:
#   ./tools/sign-app.sh <path/to/Signoff.app>
#
# Required:
#   DEVELOPER_ID_APPLICATION  — e.g. "Developer ID Application: Acme Inc (TEAMID)"
#
# Optional:
#   SIGN_ENTITLEMENTS         — defaults to Sources/SignoffApp/Signoff.entitlements
#
# Local (no cert): exits 0 with a clear skip message so unsigned local builds
# keep working. CI / release.yml must set DEVELOPER_ID_APPLICATION (fails closed
# upstream if missing).
#
# See docs/SPARKLE.md.

set -euo pipefail

APP_PATH="${1:?Usage: sign-app.sh <path/to/Signoff.app>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="${SIGN_ENTITLEMENTS:-$REPO_ROOT/Sources/SignoffApp/Signoff.entitlements}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Not an app bundle: $APP_PATH" >&2
    exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "❌ Missing entitlements at $ENTITLEMENTS" >&2
    echo "   (expected Sources/SignoffApp/Signoff.entitlements — not Resources/)" >&2
    exit 1
fi

if [ -z "$IDENTITY" ]; then
    # No Developer ID cert: re-sign ad-hoc with `codesign --force --deep`.
    # This is REQUIRED, not optional — build.sh copies SPM resource bundles and
    # patches Info.plist AFTER the linker's original signature, which invalidates
    # it. macOS refuses to honor TCC grants (Input Monitoring / Accessibility)
    # for an invalidly-signed bundle: CGEvent.tapCreate returns nil even when
    # System Settings shows the toggle on. A valid ad-hoc signature restores that.
    echo "🔐 No Developer ID — re-signing ad-hoc (valid signature for TCC grants)."
    codesign --force --deep --sign - "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    echo "✅ Ad-hoc signed (valid): $APP_PATH"
    echo "   Note: an ad-hoc signature is unique per build, so re-grant Input"
    echo "   Monitoring once after installing a freshly built copy."
    exit 0
fi

echo "🔐 Signing $APP_PATH"
echo "   identity: $IDENTITY"
echo "   entitlements: $ENTITLEMENTS"

codesign --deep --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "✅ Signed: $APP_PATH"
