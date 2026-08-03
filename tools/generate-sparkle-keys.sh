#!/usr/bin/env bash
# generate-sparkle-keys.sh — one-time EdDSA keypair for Sparkle updates.
#
# NEVER commit the private key. Store it in 1Password + GitHub Actions secret
# SPARKLE_PRIVATE_KEY. Put the public key into SU_PUBLIC_ED_KEY when bundling
# (build.sh injects it into Info.plist as SUPublicEDKey).
#
# Usage:
#   ./tools/generate-sparkle-keys.sh
#
# See docs/SPARKLE.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_VERSION="${SPARKLE_TOOLS_VERSION:-2.9.4}"
TOOLS_CACHE="${REPO_ROOT}/.build/sparkle-tools"

find_generate_keys() {
    if [ -n "${SPARKLE_TOOLS_DIR:-}" ] && [ -x "${SPARKLE_TOOLS_DIR}/generate_keys" ]; then
        echo "${SPARKLE_TOOLS_DIR}/generate_keys"
        return 0
    fi
    if command -v generate_keys >/dev/null 2>&1; then
        command -v generate_keys
        return 0
    fi
    local candidate
    for candidate in \
        "${TOOLS_CACHE}/bin/generate_keys" \
        "${REPO_ROOT}/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
    do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

ensure_generate_keys() {
    if find_generate_keys >/dev/null 2>&1; then
        return 0
    fi
    echo "ℹ️  Fetching Sparkle ${SPARKLE_VERSION} tools (includes generate_keys)…"
    mkdir -p "$TOOLS_CACHE"
    local archive="${TOOLS_CACHE}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    local url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    if [ ! -f "$archive" ]; then
        curl -fsSL -o "$archive" "$url"
    fi
    tar -xJf "$archive" -C "$TOOLS_CACHE" 2>/dev/null || tar -xf "$archive" -C "$TOOLS_CACHE"
    local found
    found="$(find "$TOOLS_CACHE" -type f -name generate_keys 2>/dev/null | head -1 || true)"
    if [ -z "$found" ]; then
        echo "❌ generate_keys not found in Sparkle ${SPARKLE_VERSION} archive." >&2
        exit 1
    fi
    mkdir -p "${TOOLS_CACHE}/bin"
    chmod +x "$found"
    ln -sfn "$found" "${TOOLS_CACHE}/bin/generate_keys"
}

ensure_generate_keys
GEN="$(find_generate_keys)"

echo "═══ Sparkle EdDSA key generation ═══"
echo ""
echo "This runs Sparkle's generate_keys. Typical flow:"
echo "  1. Private key is stored in your login Keychain (Sparkle account ed25519)"
echo "     OR exported as base64 for CI secret SPARKLE_PRIVATE_KEY."
echo "  2. Public key (base64) goes into Info.plist as SUPublicEDKey via:"
echo "       export SU_PUBLIC_ED_KEY='…public…'"
echo "       ./build.sh"
echo "  3. Until then Info.plist keeps SUPublicEDKey=REPLACE_ME and Sparkle"
echo "     stays disabled at runtime (no misconfig alert)."
echo ""
echo "Losing the private key = permanent inability to sign future appcasts."
echo ""
echo "Running: $GEN"
echo ""

"$GEN"

echo ""
echo "Next:"
echo "  • Copy the printed public key → GitHub var / local SU_PUBLIC_ED_KEY"
echo "  • Copy the private key export → 1Password + SPARKLE_PRIVATE_KEY secret"
echo "  • Never commit private key material"
