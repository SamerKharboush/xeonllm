#!/bin/zsh
# Rebuilds AppIcon.icns from icon.png (the source of truth at the repo root).
# The art is a complete illustration with its own frame, so it ships as-is in
# every size; the 512@2x/1024 slot is an upscale of the 600 px source.
#   ./scripts/make-app-icon.sh
set -e
cd "$(dirname "$0")/.."

SRC="${1:-icon.png}"
OUT="${2:-AppIcon.icns}"
[ -f "$SRC" ] || { echo "$SRC not found" >&2; exit 1; }

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" \
            "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" \
            "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
    set -- ${=spec}
    sips -s format png -z "$1" "$1" "$SRC" --out "$ICONSET/$2" > /dev/null
done
iconutil -c icns -o "$OUT" "$ICONSET"
echo "Done: $OUT"