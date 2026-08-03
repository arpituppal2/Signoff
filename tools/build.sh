#!/usr/bin/env bash
# build.sh — assemble a runnable Signoff.app from `swift build -c release` output.
#
# `swift build` emits a raw Mach-O executable plus SPM resource bundles as
# siblings in .build/out/Products/Release — NOT a proper .app. This script
# assembles the .app bundle the way macOS expects: executable in Contents/MacOS,
# Info.plist + PrivacyInfo + the SPM resource bundles in Contents/Resources.
#
# Without the SPM bundles (Signoff_SignoffCore.bundle holds the Prompt .json
# files), `Bundle.module` hits a fatalError on launch and the app silently
# quits. This is the step that was missing.
#
# Usage:
#   ./tools/build.sh             # build + assemble .build/.../Signoff.app
#   ./tools/build.sh --install    # also force-replace /Applications/Signoff.app
#                                 # (kills any running instance first)
#
# Environment:
#   SIGNOFF_INSTALL_DIR  — defaults to /Applications
#
# After this, run ./tools/sign-app.sh <path> to codesign.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

INSTALL=0
INSTALL_DIR="${SIGNOFF_INSTALL_DIR:-/Applications}"
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

echo "🔨 Building (release)…"
swift build -c release

PRODUCTS=".build/out/Products/Release"
EXEC="$PRODUCTS/Signoff"
APP="$PRODUCTS/Signoff.app"

if [ ! -f "$EXEC" ]; then
  echo "❌ Build produced no executable at $EXEC" >&2
  exit 1
fi

# Fresh bundle layout.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Executable.
cp "$EXEC" "$APP/Contents/MacOS/Signoff"

# Info.plist (from source — swift build does not bundle it).
cp "Sources/SignoffApp/Info.plist" "$APP/Contents/Info.plist"

# PrivacyInfo.xcprivacy into Resources.
cp "Sources/SignoffApp/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/"

# SPM resource bundles into Contents/Resources — the bundle accessor
# (Bundle.module) searches Bundle.main.resourceURL, which is Contents/Resources.
# Signoff_SignoffCore.bundle carries the generation Prompt .json files and is
# load‑bearing: without it the app fatalErrors on launch.
for bundle in "$PRODUCTS"/Signoff_*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$APP/Contents/Resources/"
done

echo "✅ Assembled: $APP"
echo "   Contents/Resources:"; ls "$APP/Contents/Resources" | sed 's/^/     /'

if [ "$INSTALL" -eq 1 ]; then
  echo "🔐 Signing (ad-hoc)…"
  ./tools/sign-app.sh "$APP" >/dev/null

  # Kill any running instance so the binary isn't busy.
  pkill -x Signoff 2>/dev/null || true
  sleep 1

  echo "📦 Installing to $INSTALL_DIR/Signoff.app …"
  rm -rf "$INSTALL_DIR/Signoff.app"
  cp -R "$APP" "$INSTALL_DIR/Signoff.app"

  echo "🚀 Launching…"
  open "$INSTALL_DIR/Signoff.app"
  echo "✅ Installed. Re-grant Input Monitoring once for the new ad-hoc signature."
fi
