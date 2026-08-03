#!/usr/bin/env bash
# create-dmg.sh — branded DMG installer for Signoff.app
# Usage: ./tools/create-dmg.sh <path/to/Signoff.app> <version-string>
# Per PERFECTION_PLAN_V2_AUTOPLAN_REVIEW.md TASK-7.
#
# Resilience notes:
# - Missing background PNG is OK (Apple-style default layout).
# - Resolves .app to an absolute path; validates Info.plist.
# - Detaches stale /Volumes mounts; retries hdiutil create up to 3 times.
# - Cleans staging via EXIT trap even on failure.
# - Does not require the optional create-dmg(1) Homebrew formula.

set -euo pipefail

APP_PATH="${1:?Usage: create-dmg.sh <.app path> <version>}"
VERSION="${2:?Usage: create-dmg.sh <.app path> <version>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Strip leading "v" so tags like v1.0.0 and plain 1.0.0 both work.
VERSION="${VERSION#v}"
DMG_NAME="Signoff-${VERSION}"
DMG_PATH="${REPO_ROOT}/${DMG_NAME}.dmg"
BACKGROUND_IMAGE="${REPO_ROOT}/Resources/dmg-background.png"

WINDOW_WIDTH=540
WINDOW_HEIGHT=360
# Reserved for future create-dmg(1) branded layout; hdiutil path ignores these today.
: "${WINDOW_WIDTH}" "${WINDOW_HEIGHT}"

# Normalize to absolute path (avoids cwd surprises from CI / callers).
if [[ "${APP_PATH}" != /* ]]; then
    APP_PATH="$(cd "$(dirname "${APP_PATH}")" && pwd)/$(basename "${APP_PATH}")"
fi

if [ ! -d "${APP_PATH}" ]; then
    echo "❌ App not found: ${APP_PATH}" >&2
    exit 1
fi

if [ ! -f "${APP_PATH}/Contents/Info.plist" ]; then
    echo "❌ Not a valid .app bundle (missing Contents/Info.plist): ${APP_PATH}" >&2
    exit 1
fi

if [ -f "${BACKGROUND_IMAGE}" ]; then
    echo "ℹ️  Background image present at ${BACKGROUND_IMAGE} (hdiutil UDZO ignores custom window chrome; ship create-dmg later for branded layout)."
else
    echo "ℹ️  No Resources/dmg-background.png — using default Apple-style drag-to-Applications layout."
fi

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/signoff-dmg.XXXXXX")"
detach_stale() {
    # Best-effort: free volume name + any prior mount of this DMG path.
    if [ -d "/Volumes/${DMG_NAME}" ]; then
        hdiutil detach "/Volumes/${DMG_NAME}" -force >/dev/null 2>&1 || true
    fi
    if [ -f "${DMG_PATH}" ]; then
        hdiutil detach "${DMG_PATH}" -force >/dev/null 2>&1 || true
    fi
}
cleanup() {
    detach_stale
    rm -rf "${STAGING}"
}
trap cleanup EXIT

detach_stale
rm -f "${DMG_PATH}"
cp -R "${APP_PATH}" "${STAGING}/Signoff.app"
ln -sf /Applications "${STAGING}/Applications"
sync

create_dmg() {
    hdiutil create \
        -volname "${DMG_NAME}" \
        -srcfolder "${STAGING}" \
        -ov \
        -format UDZO \
        -fs HFS+ \
        -imagekey zlib-level=9 \
        "${DMG_PATH}"
}

attempts=0
max_attempts=3
until create_dmg; do
    attempts=$((attempts + 1))
    if [ "${attempts}" -ge "${max_attempts}" ]; then
        echo "❌ hdiutil create failed after ${max_attempts} attempts." >&2
        exit 1
    fi
    echo "⚠️  hdiutil create failed — retry ${attempts}/${max_attempts} after detach…" >&2
    detach_stale
    rm -f "${DMG_PATH}"
    sleep $((attempts * 2))
    sync
done

echo "✅ Built ${DMG_PATH} ($(du -h "${DMG_PATH}" | cut -f1))"
