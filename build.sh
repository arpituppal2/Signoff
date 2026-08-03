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
# Default points at a GitHub release asset (publish appcast.json alongside
# future releases to enable auto-update). Kept configurable for self-hosting.
SU_FEED_URL="${SU_FEED_URL:-https://github.com/arpituppal2/Signoff/releases/latest/download/appcast.json}"

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

# ── Copy SPM resource bundles into the .app ─────────────────────
# SwiftPM emits a resource bundle per target (Signoff_SignoffCore.bundle,
# Signoff_SignoffApp.bundle, …) holding .process()'d resources. `Bundle.module`
# in the generated resource_bundle_accessor looks for these in Bundle.main's
# resourceURL — i.e. <app>/Contents/Resources/. Without copying them,
# PromptTemplate.load() → Bundle.module fatally traps (EXC_BREAKPOINT) on
# launch, even though `swift run` works (SPM stages the bundles beside the
# binary). Placed before code-signing so `sign-app.sh --deep` covers them.
BUNDLES_COPIED=0
shopt -s nullglob
for b in "$BUILD_DIR/release"/*.bundle; do
    cp -R "$b" "$APP_BUNDLE/Contents/Resources/"
    BUNDLES_COPIED=$((BUNDLES_COPIED + 1))
done
shopt -u nullglob
if [ "$BUNDLES_COPIED" -eq 0 ]; then
    echo "❌ No SPM resource bundles found in $BUILD_DIR/release — app would crash at launch (Bundle.module)"
    echo "   Run 'swift build -c release' first, or ensure Package.swift lists target resources."
    exit 1
fi
echo "✅ Copied $BUNDLES_COPIED resource bundle(s) into Contents/Resources/"
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

# ── Create DMG with Applications alias and custom background ────────────────────────
# This block builds a DMG that contains the app bundle, an Applications alias for drag‑and‑drop,
# and uses the "Signoff Word" image as the DMG background.
# ---------------------------------------------------------------------
# Prepare temporary layout directory
TMP_DMG_DIR="$(mktemp -d)"
mkdir -p "$TMP_DMG_DIR"

# Copy the .app bundle into the layout folder
cp -R "$APP_BUNDLE" "$TMP_DMG_DIR/"

# ---------------------------------------------------------------------
# Add an Applications alias (standard macOS installer style)
# The alias points to the real /Applications folder.
osascript <<EOF
set srcPath to POSIX file "/Applications" as alias
set dstFolder to POSIX file "$TMP_DMG_DIR" as alias
tell application "Finder"
    make new alias to srcPath at folder dstFolder
    set name of result to "Applications"
end tell
EOF

# ---------------------------------------------------------------------
# Add custom background (Signoff Word image)
BG_SRC="${PROJECT_DIR}/../Singoff Word.jpg"
BG_PNG="$TMP_DMG_DIR/background.png"
sips -s format png "$BG_SRC" --out "$BG_PNG"

# ---------------------------------------------------------------------
# Create a .DS_Store to set window layout, background, and icon positions
# Create a .DS_Store to set window layout, background, and icon positions.
# Cosmetic only — Finder scripting can flake (error -10006) when the window
# hasn't finished opening, so a failure warns but does not abort the build.
if ! osascript <<EOF
    tell application "Finder"
        set dmgFolder to POSIX file "$TMP_DMG_DIR" as alias
        open dmgFolder
        delay 1
        set viewOptions to the container window of dmgFolder
        set current view of viewOptions to icon view
        set the bounds of viewOptions to {100, 100, 620, 420}
        set the background picture of viewOptions to file "background.png"
        set position of item "$APP_NAME.app" of dmgFolder to {187, 150}
        set position of item "Applications" of dmgFolder to {533, 150}
        close
    end tell
EOF
then
    echo "⚠️  Finder layout scripting failed — DMG will use default window layout."
fi

# ---------------------------------------------------------------------
# Build the compressed DMG from the temporary layout
DMG_PATH="${BUILD_DIR}/release/${DMG_NAME}"
rm -f "$DMG_PATH"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$TMP_DMG_DIR" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDZO -ov "$DMG_PATH"

# Clean up temporary folder
rm -rf "$TMP_DMG_DIR"

# ---------------------------------------------------------------------
# Report success
echo "✅ DMG created at $DMG_PATH (contains Applications alias and custom background)"

