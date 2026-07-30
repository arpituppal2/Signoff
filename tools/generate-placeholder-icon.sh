#!/usr/bin/env bash
# generate-placeholder-icon.sh — solid Signoff Amber (#D4A017) AppIcon placeholder.
# Produces Resources/Assets.xcassets/AppIcon.appiconset/*.png + Resources/AppIcon.icns
# Replace with Icon Composer art before marketing (see Resources/README.md).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPSET="$REPO_ROOT/Resources/Assets.xcassets/AppIcon.appiconset"
ICNS_OUT="$REPO_ROOT/Resources/AppIcon.icns"
TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"

mkdir -p "$APPSET" "$TMP_ICONSET"

MASTER="$TMP_ICONSET/_master.png"
# 32×32 amber PNG via Python (stdlib only).
python3 - "$MASTER" <<'PY'
import struct, zlib, sys
path, w, h = sys.argv[1], 32, 32
r, g, b, a = 0xD4, 0xA0, 0x17, 0xFF
rows = b"".join(b"\x00" + bytes([r, g, b, a]) * w for _ in range(h))

def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
open(path, "wb").write(
    b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows, 1)) + chunk(b"IEND", b"")
)
print(path)
PY

# Scale with sips into iconutil + appiconset names.
declare -a SPECS=(
  "16:icon_16x16.png"
  "32:diana.k@example.org"
  "32:icon_32x32.png"
  "64:ivan.p@example.net"
  "128:icon_128x128.png"
  "256:wendy.h@example.net"
  "256:icon_256x256.png"
  "512:wendy.h@example.net"
  "512:icon_512x512.png"
  "1024:walt.e@example.net"
)

for spec in "${SPECS[@]}"; do
  px="${spec%%:*}"
  name="${spec#*:}"
  # sips warns on some @2x paths — write to a plain .png then rename.
  tmp_png="$TMP_ICONSET/_scaled_${px}.png"
  sips -z "$px" "$px" "$MASTER" --out "$tmp_png" >/dev/null
  cp "$tmp_png" "$TMP_ICONSET/$name"
  cp "$tmp_png" "$APPSET/$name"
done

iconutil -c icns "$TMP_ICONSET" -o "$ICNS_OUT"
rm -rf "$(dirname "$TMP_ICONSET")"
echo "✅ Placeholder icon: $ICNS_OUT"
echo "   Appiconset: $APPSET"
echo "   (amber solid — swap for pen-nib brand art before public launch)"
