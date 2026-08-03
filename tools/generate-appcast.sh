#!/usr/bin/env bash
# generate-appcast.sh — wrap Sparkle's generate_appcast for Signoff releases.
#
# Usage:
#   ./tools/generate-appcast.sh <path/to/Signoff-VERSION.dmg> [--ed-key-env VAR] [--ed-key-file PATH]
#   ./tools/generate-appcast.sh --scaffold-only
#
# Behaviour:
#   1. Locates Sparkle CLI tools (PATH, SPARKLE_TOOLS_DIR, cached download).
#   2. With a private EdDSA key: runs generate_appcast and writes ./appcast.xml.
#   3. Without tools/key: --scaffold-only copies Resources/appcast.xml → ./appcast.xml
#      (still contains REPLACE_ME — not shippable).
#
# CI (release.yml) passes --ed-key-env SPARKLE_PRIVATE_KEY and expects a signed feed.
#
# See docs/SPARKLE.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_APPCAST="${REPO_ROOT}/appcast.xml"
SCAFFOLD="${REPO_ROOT}/Resources/appcast.xml"
SPARKLE_VERSION="${SPARKLE_TOOLS_VERSION:-2.9.4}"
TOOLS_CACHE="${REPO_ROOT}/.build/sparkle-tools"
DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-}"

DMG_PATH=""
ED_KEY_ENV=""
ED_KEY_FILE=""
SCAFFOLD_ONLY=0

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --scaffold-only) SCAFFOLD_ONLY=1; shift ;;
        --ed-key-env) ED_KEY_ENV="${2:?}"; shift 2 ;;
        --ed-key-file) ED_KEY_FILE="${2:?}"; shift 2 ;;
        -h|--help) usage ;;
        -*)
            echo "❌ Unknown option: $1" >&2
            usage
            ;;
        *)
            if [ -n "$DMG_PATH" ]; then
                echo "❌ Unexpected argument: $1" >&2
                usage
            fi
            DMG_PATH="$1"
            shift
            ;;
    esac
done

if [ "$SCAFFOLD_ONLY" -eq 1 ]; then
    if [ ! -f "$SCAFFOLD" ]; then
        echo "❌ Missing scaffold at $SCAFFOLD" >&2
        exit 1
    fi
    cp "$SCAFFOLD" "$OUT_APPCAST"
    echo "⚠️  Wrote scaffold appcast to $OUT_APPCAST (still has REPLACE_ME — not shippable)."
    exit 0
fi

if [ -z "$DMG_PATH" ]; then
    echo "❌ DMG path required (or use --scaffold-only)." >&2
    usage
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found: $DMG_PATH" >&2
    exit 1
fi

# Resolve private key material.
KEY_TMP=""
cleanup() {
    if [ -n "${KEY_TMP:-}" ] && [ -f "${KEY_TMP}" ]; then
        rm -f "$KEY_TMP"
    fi
}
trap cleanup EXIT

resolve_key_file() {
    if [ -n "$ED_KEY_FILE" ]; then
        if [ ! -f "$ED_KEY_FILE" ]; then
            echo "❌ --ed-key-file not found: $ED_KEY_FILE" >&2
            exit 1
        fi
        echo "$ED_KEY_FILE"
        return
    fi
    if [ -n "$ED_KEY_ENV" ]; then
        if [ -z "${!ED_KEY_ENV:-}" ]; then
            echo "❌ Environment variable $ED_KEY_ENV is empty — cannot sign appcast." >&2
            echo "   Generate keys per docs/SPARKLE.md and set SPARKLE_PRIVATE_KEY." >&2
            exit 1
        fi
        KEY_TMP="$(mktemp "${TMPDIR:-/tmp}/signoff-sparkle-ed.XXXXXX")"
        # Key may be raw base64 or include a trailing newline from secrets UI.
        printf '%s' "${!ED_KEY_ENV}" | tr -d '\r' > "$KEY_TMP"
        echo "$KEY_TMP"
        return
    fi
    echo "❌ Provide --ed-key-env SPARKLE_PRIVATE_KEY or --ed-key-file <path>." >&2
    echo "   For unsigned local scaffolding only: ./tools/generate-appcast.sh --scaffold-only" >&2
    exit 1
}

find_tool() {
    local name="$1"
    if [ -n "${SPARKLE_TOOLS_DIR:-}" ] && [ -x "${SPARKLE_TOOLS_DIR}/${name}" ]; then
        echo "${SPARKLE_TOOLS_DIR}/${name}"
        return 0
    fi
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi
    local candidate
    for candidate in \
        "${TOOLS_CACHE}/bin/${name}" \
        "${REPO_ROOT}/.build/artifacts/sparkle/Sparkle/bin/${name}" \
        "${REPO_ROOT}/.build/checkouts/Sparkle/bin/${name}"
    do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

ensure_sparkle_tools() {
    if find_tool generate_appcast >/dev/null 2>&1; then
        return 0
    fi
    echo "ℹ️  Sparkle generate_appcast not on PATH — fetching ${SPARKLE_VERSION} tools…"
    mkdir -p "$TOOLS_CACHE"
    local archive="${TOOLS_CACHE}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    local url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    if [ ! -f "$archive" ]; then
        curl -fsSL -o "$archive" "$url"
    fi
    # Archive extracts to a bin/ directory; flatten into TOOLS_CACHE.
    tar -xJf "$archive" -C "$TOOLS_CACHE" --strip-components=0 2>/dev/null \
        || tar -xf "$archive" -C "$TOOLS_CACHE"
    # Locate generate_appcast wherever tar put it.
    local found
    found="$(find "$TOOLS_CACHE" -type f -name generate_appcast 2>/dev/null | head -1 || true)"
    if [ -z "$found" ]; then
        echo "❌ Downloaded Sparkle ${SPARKLE_VERSION} but generate_appcast is missing." >&2
        echo "   Set SPARKLE_TOOLS_DIR to a directory containing generate_appcast." >&2
        exit 1
    fi
    chmod +x "$found" || true
    # Symlink into TOOLS_CACHE/bin for stable path.
    mkdir -p "${TOOLS_CACHE}/bin"
    ln -sfn "$found" "${TOOLS_CACHE}/bin/generate_appcast"
    local sign_found
    sign_found="$(find "$TOOLS_CACHE" -type f -name sign_update 2>/dev/null | head -1 || true)"
    if [ -n "$sign_found" ]; then
        chmod +x "$sign_found" || true
        ln -sfn "$sign_found" "${TOOLS_CACHE}/bin/sign_update"
    fi
}

ensure_sparkle_tools
GENERATE_APPCAST="$(find_tool generate_appcast)" || {
    echo "❌ generate_appcast not found after ensure step." >&2
    exit 1
}

KEY_FILE="$(resolve_key_file)"

# generate_appcast expects a directory of archives, not a single file path.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/signoff-appcast.XXXXXX")"
cleanup_work() {
    cleanup
    rm -rf "$WORK"
}
trap cleanup_work EXIT

cp "$DMG_PATH" "$WORK/$(basename "$DMG_PATH")"

GEN_ARGS=(--ed-key-file - --disable-signing-warning)
if [ -n "$DOWNLOAD_URL_PREFIX" ]; then
    GEN_ARGS+=(--download-url-prefix "$DOWNLOAD_URL_PREFIX")
fi
GEN_ARGS+=(--link "https://github.com/arpituppal2/Signoff")

echo "📜 Generating appcast from $(basename "$DMG_PATH") via $GENERATE_APPCAST"
# Sparkle reads the private key from stdin when --ed-key-file is '-'.
cat "$KEY_FILE" | "$GENERATE_APPCAST" "${GEN_ARGS[@]}" "$WORK"

# generate_appcast writes appcast.xml into the archives directory.
if [ -f "$WORK/appcast.xml" ]; then
    cp "$WORK/appcast.xml" "$OUT_APPCAST"
elif [ -f "${REPO_ROOT}/appcast.xml" ]; then
    : # already at repo root
else
    # Some Sparkle versions write next to CWD.
    if [ -f ./appcast.xml ]; then
        cp ./appcast.xml "$OUT_APPCAST"
    else
        echo "❌ generate_appcast finished but appcast.xml was not produced." >&2
        exit 1
    fi
fi

if grep -q 'REPLACE_ME' "$OUT_APPCAST" 2>/dev/null; then
    echo "❌ appcast.xml still contains REPLACE_ME — refusing to treat as signed." >&2
    exit 1
fi

echo "✅ Wrote signed appcast: $OUT_APPCAST"
