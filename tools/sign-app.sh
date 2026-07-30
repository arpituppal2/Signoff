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
    echo "⚠️  DEVELOPER_ID_APPLICATION unset — skipping codesign (local unsigned build)."
    echo "   Ship path needs a Developer ID Application cert in the keychain."
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
