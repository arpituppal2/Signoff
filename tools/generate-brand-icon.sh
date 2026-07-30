#!/usr/bin/env bash
# generate-brand-icon.sh — Signoff branded App Icon (period motif).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPSET="$REPO_ROOT/Resources/Assets.xcassets/AppIcon.appiconset"
ICNS_OUT="$REPO_ROOT/Resources/AppIcon.icns"
TMPDIR="$(mktemp -d)"
TMP_ICONSET="$TMPDIR/AppIcon.iconset"

mkdir -p "$APPSET" "$TMP_ICONSET"

# Generate master 1024x1024 PNG via Python
MASTER_PNG="$TMP_ICONSET/_master.png"
python3 -c "
import struct, zlib, math

W, H = 1024, 1024
cx, cy = W // 2, H // 2

bg_top = (0xE8, 0xC2, 0x4A)
bg_bot = (0xD4, 0xA0, 0x17)
period_rgb = (0xFF, 0xFF, 0xFF)
period_radius = 200
shadow_offset = 8

def dist(x1, y1, x2, y2):
    return math.sqrt((x1-x2)**2 + (y1-y2)**2)

def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)

pixels = bytearray()
for y in range(H):
    row = bytearray()
    row.append(0)
    bg_t = y / H
    bg_r = int(bg_top[0] + (bg_bot[0] - bg_top[0]) * bg_t)
    bg_g = int(bg_top[1] + (bg_bot[1] - bg_top[1]) * bg_t)
    bg_b = int(bg_top[2] + (bg_bot[2] - bg_top[2]) * bg_t)
    for x in range(W):
        d = dist(x, y, cx, cy)
        sd = dist(x, y, cx + shadow_offset, cy + shadow_offset)
        shadow = smoothstep(period_radius + 2, period_radius - 2, sd) * 0.3
        pa = smoothstep(period_radius + 2, period_radius - 2, d)
        if pa > 0 and shadow > 0:
            s = shadow * (1 - pa)
            r = int(bg_r * (1 - s - pa) + period_rgb[0] * pa)
            g = int(bg_g * (1 - s - pa) + period_rgb[1] * pa)
            b = int(bg_b * (1 - s - pa) + period_rgb[2] * pa)
        elif pa > 0:
            r = int(bg_r * (1 - pa) + period_rgb[0] * pa)
            g = int(bg_g * (1 - pa) + period_rgb[1] * pa)
            b = int(bg_b * (1 - pa) + period_rgb[2] * pa)
        else:
            r, g, b = bg_r, bg_g, bg_b
        row.extend([r, g, b, 255])
    pixels.extend(row)

def chunk(tag, data):
    crc = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', crc)

ihdr = struct.pack('>IIBBBBB', W, H, 8, 6, 0, 0, 0)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(pixels, 1)) + chunk(b'IEND', b'')

with open('$MASTER_PNG', 'wb') as f:
    f.write(png)
print('Master generated:', '$MASTER_PNG')
"

# Scale to all required sizes
declare -a SPECS=(
  "16:icon_16x16.png"
  "32:icon_32x32.png"
  "32:icon_16x16@2x.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
  "1024:icon_1024.png"
)

for spec in "${SPECS[@]}"; do
  px="${spec%%:*}"
  name="${spec#*:}"
  tmp_png="$TMP_ICONSET/_scaled_${px}.png"
  sips -z "$px" "$px" "$MASTER_PNG" --out "$tmp_png" >/dev/null 2>&1
  cp "$tmp_png" "$TMP_ICONSET/$name"
  cp "$tmp_png" "$APPSET/$name"
done

# Update Contents.json
cat > "$APPSET/Contents.json" <<'JSON'
{
  "images" : [
    {"size":"16x16","filename":"icon_16x16.png","idiom":"mac"},
    {"size":"16x16","filename":"icon_16x16@2x.png","idiom":"mac","scale":"2x"},
    {"size":"32x32","filename":"icon_32x32.png","idiom":"mac"},
    {"size":"32x32","filename":"icon_32x32@2x.png","idiom":"mac","scale":"2x"},
    {"size":"128x128","filename":"icon_128x128.png","idiom":"mac"},
    {"size":"128x128","filename":"icon_128x128@2x.png","idiom":"mac","scale":"2x"},
    {"size":"256x256","filename":"icon_256x256.png","idiom":"mac"},
    {"size":"256x256","filename":"icon_256x256@2x.png","idiom":"mac","scale":"2x"},
    {"size":"512x512","filename":"icon_512x512.png","idiom":"mac"},
    {"size":"512x512","filename":"icon_512x512@2x.png","idiom":"mac","scale":"2x"},
    {"size":"1024x1024","filename":"icon_1024.png","idiom":"mac"}
  ],
  "info" : {"version" : 1, "author" : "Signoff"}
}
JSON

# Clean up old placeholder files
for f in "$APPSET"/*; do
  base="$(basename "$f")"
  if [[ "$base" == *@*.* && "$base" != icon_* ]]; then
    rm -f "$f"
  fi
done

# Generate .icns
iconutil -c icns "$TMP_ICONSET" -o "$ICNS_OUT"

rm -rf "$TMPDIR"
echo "✅ Brand icon: $ICNS_OUT"
echo "   Design: Amber gradient + white period motif"
