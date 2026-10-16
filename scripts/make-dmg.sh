#!/bin/bash
#
# Package NetworkSentinel.app into a DMG that opens on the app next to an
# Applications shortcut, so installing is one drag.
#
# Usage: scripts/make-dmg.sh <path/to/NetworkSentinel.app> <output.dmg>
#
set -euo pipefail

APP="$1"
OUT="$2"

if [ ! -d "$APP" ]; then
    echo "error: app not found: $APP" >&2
    exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Network Sentinel.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "Network Sentinel" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$OUT"

echo "Wrote $OUT"
