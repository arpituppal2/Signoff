#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Signoff"
DMG_NAME="Signoff.dmg"
NOTARY_PROFILE="SignoffNotary"
INFO_PLIST="$PROJECT_DIR/Sources/SignoffApp/Info.plist"
ENTITLEMENTS="$PROJECT_DIR/Sources/SignoffApp/Signoff.entitlements"
PRIVACY_MANIFEST="$PROJECT_DIR/Sources/SignoffApp/PrivacyInfo.xcprivacy"
APP_ICON_ICNS="$PROJECT_DIR/Resources/AppIcon.icns"
APPICONSET="$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
# Update feed URL — injected into the bundled Info.plist.
# Default keeps REPLACE_ME so local builds do not pretend to ship updates.
SU_FEED_URL="${SU_FEED_URL:-https://signoff.app/appcast.json}"

echo "═══ Signoff Build & Notarization Pipeline ═══"
echo ""

# ── Preflight (align with Package.swift + release.yml) ───────
if [ ! -f "$INFO_PLIST" ]; then
    echo "❌ Missing Info.plist at $INFO_PLIST"
    exit 1
fi
if [ ! -f "$ENTITLEMENTS" ]; then
    echo "❌ Missing entitlements at $ENTITLEMENTS"
    exit 1
fi
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST" 2>/dev/null || true)"
if [ "$MIN_OS" != "26.0" ]; then
    echo "❌ Info.plist LSMinimumSystemVersion must be 26.0 (found: '${MIN_OS:-missing}') to match Package.swift"
    exit 1
fi
LSUI="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$INFO_PLIST" 2>/dev/null || true)"
# PlistBuddy prints "true" for boolean YES.
if [ "$LSUI" != "true" ]; then
    echo "❌ Info.plist LSUIElement must be true (menu-bar / accessory; found: '${LSUI:-missing}')"
    exit 1
fi
AE_USAGE="$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$INFO_PLIST" 2>/dev/null || true)"
if [ -z "$AE_USAGE" ]; then
    echo "❌ Info.plist must include NSAppleEventsUsageDescription (Apple Events entitlement)"
    exit 1
fi
SU_FEED_SRC="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO_PLIST" 2>/dev/null || true)"
if [ -z "$SU_FEED_SRC" ]; then
    echo "❌ Info.plist must include SUFeedURL (see docs/SPARKLE.md)"
    exit 1
fi
# Accessibility / Input Monitoring: no Info.plist usage strings on macOS — TCC only.
# Documented in Info.plist comments + docs/NOTARIZATION.md.

# ── Clean & Build ────────────────────────────────────────────
echo "🔨 Building Signoff (release)..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "❌ Binary not found at $BINARY"
    exit 1
fi
echo "✅ Build complete: $BINARY"
echo ""

# ── Bundle into .app structure ───────────────────────────────
echo "📦 Creating app bundle..."
APP_BUNDLE="$BUILD_DIR/release/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist — source of truth, then inject feed URL for this build.
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
BUNDLE_PLIST="$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL ${SU_FEED_URL}" "$BUNDLE_PLIST"
echo "📡 Feed URL: ${SU_FEED_URL}"

# Privacy Manifest into bundle (fail loud if missing — required for notarization review).
if [ -f "$PRIVACY_MANIFEST" ]; then
    cp "$PRIVACY_MANIFEST" "$APP_BUNDLE/Contents/Resources/"
else
    echo "⚠️  PrivacyInfo.xcprivacy missing at $PRIVACY_MANIFEST"
fi

# App icon — prefer prebuilt icns; else build from appiconset via iconutil.
if [ -f "$APP_ICON_ICNS" ]; then
    cp "$APP_ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "✅ Bundled AppIcon.icns (placeholder OK — see Resources/README.md)"
elif [ -d "$APPICONSET" ] && command -v iconutil >/dev/null 2>&1; then
    TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$TMP_ICONSET"
    # Map appiconset PNGs into iconutil layout when present.
    for f in "$APPICONSET"/icon_*.png; do
        [ -f "$f" ] || continue
        cp "$f" "$TMP_ICONSET/$(basename "$f")"
    done
    if iconutil -c icns "$TMP_ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null; then
        echo "✅ Built AppIcon.icns from Assets.xcassets/AppIcon.appiconset"
    else
        echo "⚠️  iconutil failed — app will use the generic macOS icon"
    fi
    rm -rf "$(dirname "$TMP_ICONSET")"
else
    echo "⚠️  No Resources/AppIcon.icns (and no appiconset) — generic Finder icon until assets land"
fi
echo "✅ App bundle created at $APP_BUNDLE"
echo ""

# ── Code Sign (Developer ID) via tools/sign-app.sh ────────────
echo "🔐 Code signing with Developer ID..."
"$PROJECT_DIR/tools/sign-app.sh" "$APP_BUNDLE"
echo ""

# ── Notarize (.app) ───────────────────────────────────────────
# Local: keychain profile SignoffNotary (see docs/NOTARIZATION.md).
# CI: App Store Connect API key env vars, OR SKIP_NOTARIZATION=1 when the
#     workflow notarizes the versioned DMG instead (release.yml).
echo "📋 Notarizing..."
DEVELOPER_ID="${DEVELOPER_ID_APPLICATION:-}"
SKIP_NOTARY="${SKIP_NOTARIZATION:-0}"
if [ "$SKIP_NOTARY" = "1" ] || [ "$SKIP_NOTARY" = "true" ]; then
    echo "⚠️  SKIP_NOTARIZATION set — not notarizing .app (DMG path owns notary)."
elif [ -z "$DEVELOPER_ID" ]; then
    echo "⚠️  Skipping notarization (no Developer ID)."
else
    ZIP_PATH="$BUILD_DIR/release/$APP_NAME.zip"
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    submit_ok=0
    if [ -n "${APP_STORE_CONNECT_API_KEY_P8:-}" ] \
        && [ -n "${APP_STORE_CONNECT_KEY_ID:-}" ] \
        && [ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]; then
        KEY_FILE="$(mktemp "${TMPDIR:-/tmp}/signoff-asc.XXXXXX")"
        printf '%s' "$APP_STORE_CONNECT_API_KEY_P8" > "$KEY_FILE"
        if xcrun notarytool submit "$ZIP_PATH" \
            --key "$KEY_FILE" \
            --key-id "$APP_STORE_CONNECT_KEY_ID" \
            --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
            --wait; then
            submit_ok=1
        fi
        rm -f "$KEY_FILE"
    else
        # Local path: credentials stored via `notarytool store-credentials`.
        if xcrun notarytool submit "$ZIP_PATH" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait; then
            submit_ok=1
        else
            echo "❌ Notarization failed via keychain profile '$NOTARY_PROFILE'."
            echo "   Store credentials: xcrun notarytool store-credentials $NOTARY_PROFILE …"
            echo "   Or set APP_STORE_CONNECT_API_KEY_P8 / KEY_ID / ISSUER_ID,"
            echo "   or SKIP_NOTARIZATION=1 and notarize the DMG instead."
            echo "   See docs/NOTARIZATION.md."
            exit 1
        fi
    fi

    if [ "$submit_ok" -eq 1 ]; then
        echo "✅ Notarization accepted."
        xcrun stapler staple "$APP_BUNDLE"
        echo "✅ Ticket stapled to $APP_BUNDLE"
    else
        echo "❌ Notarization failed."
        exit 1
    fi
fi
echo ""

# ── Create DMG ────────────────────────────────────────────────
echo "💿 Creating DMG..."
DMG_PATH="$BUILD_DIR/release/$DMG_NAME"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" \
    -ov -format UDZO "$DMG_PATH" 2>&1
echo "✅ DMG created at $DMG_PATH"
echo ""
echo "═══ Ship pipeline complete ═══"
echo "DMG: $DMG_PATH"
