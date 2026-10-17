#!/bin/bash
#
# Regenerate NetworkSentinel/Assets.xcassets/AppIcon.appiconset from
# Design/Icons/AppIcon-Dark.svg.
#
# The SVG is rendered once at 1024x1024 (WebKit, via scripts/render-svg.swift),
# then scaled down with sips to every size macOS asks for.
# Re-run this script after changing the artwork; it rewrites the PNGs and
# AppIcon.appiconset/Contents.json.
#
# Usage: ./scripts/make-app-icon.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

SVG="Design/Icons/AppIcon-Dark-FullBleed.svg"
RENDERER="scripts/render-svg.swift"
ICONSET="NetworkSentinel/Assets.xcassets/AppIcon.appiconset"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

if [ ! -f "$SVG" ]; then
    echo "error: missing source artwork: $SVG" >&2
    exit 1
fi
if [ ! -f "$RENDERER" ]; then
    echo "error: missing renderer: $RENDERER" >&2
    exit 1
fi

mkdir -p "$ICONSET"

WORK_DIR=".build/icon"
mkdir -p "$WORK_DIR"
MASTER="$WORK_DIR/appicon-1024.png"

# A module cache inside the repository keeps the toolchain from writing to ~/Library.
echo "Building SVG renderer ..."
xcrun swiftc -O \
    -module-cache-path "$PWD/.build/module-cache" \
    -o "$WORK_DIR/render-svg" \
    "$RENDERER"

echo "Rendering $SVG at 1024x1024 ..."
"$WORK_DIR/render-svg" "$SVG" "$MASTER" 1024

# pixels:filename — covers every macOS slot (16/32/128/256/512 at 1x and 2x).
SPECS=(
    "16:icon_16x16"
    "32:icon_16x16@2x"
    "32:icon_32x32"
    "64:icon_32x32@2x"
    "128:icon_128x128"
    "256:icon_128x128@2x"
    "256:icon_256x256"
    "512:icon_256x256@2x"
    "512:icon_512x512"
    "1024:icon_512x512@2x"
)

for spec in "${SPECS[@]}"; do
    pixels="${spec%%:*}"
    name="${spec##*:}"
    echo "  ${name}.png (${pixels}x${pixels})"
    sips -z "$pixels" "$pixels" "$MASTER" --out "$ICONSET/${name}.png" > /dev/null
done

cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "Wrote $(ls "$ICONSET"/*.png | wc -l | tr -d ' ') PNGs and Contents.json to $ICONSET"
