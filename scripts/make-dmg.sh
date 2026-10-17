#!/bin/bash
#
# Package NetworkSentinel.app into a DMG that opens on the app next to an
# Applications shortcut, so installing is one drag.
#
# The Finder layout (window size, icon positions, path bar, background) is
# written into .DS_Store by dmgbuild, so the build does not drive Finder with
# AppleScript and works on headless CI runners too. The background artwork is
# rendered from Design/DMG/Background.svg at 1x and 2x and merged into one
# HiDPI TIFF with tiffutil.
#
# Usage: scripts/make-dmg.sh <path/to/NetworkSentinel.app> <output.dmg>
#
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: scripts/make-dmg.sh <path/to/NetworkSentinel.app> <output.dmg>" >&2
    exit 2
fi

# Resolve the arguments before changing directory, so they keep working the way
# the caller wrote them.
case "$1" in
    /*) APP="$1" ;;
    *) APP="$PWD/$1" ;;
esac
case "$2" in
    /*) OUT="$2" ;;
    *) OUT="$PWD/$2" ;;
esac

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

if [ ! -d "$APP" ]; then
    echo "error: app not found: $APP" >&2
    exit 1
fi

WORK_DIR="$REPO_ROOT/.build/dmg"
VENV="$REPO_ROOT/build/dmgbuild-venv"
DMGBUILD="$VENV/bin/dmgbuild"
mkdir -p "$WORK_DIR"

# dmgbuild writes .DS_Store itself. A local build/dmgbuild-venv is reused;
# GitHub Actions and fresh machines get one installed here.
if [ ! -x "$DMGBUILD" ]; then
    PYTHON=""
    for candidate in python3 python3.13 python3.12 python3.11 python3.10; do
        command -v "$candidate" > /dev/null 2>&1 || continue
        if "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
            PYTHON="$candidate"
            break
        fi
    done
    if [ -z "$PYTHON" ]; then
        echo "error: dmgbuild 1.6.7 needs Python 3.10 or newer" >&2
        exit 1
    fi

    echo "Installing dmgbuild 1.6.7 ..."
    "$PYTHON" -m venv "$VENV"
    "$VENV/bin/pip" install --disable-pip-version-check --quiet "dmgbuild==1.6.7"
fi

BACKGROUND_SVG="$REPO_ROOT/Design/DMG/Background.svg"
if [ ! -f "$BACKGROUND_SVG" ]; then
    echo "error: missing background artwork: $BACKGROUND_SVG" >&2
    exit 1
fi

echo "Building SVG renderer ..."
xcrun swiftc -O \
    -module-cache-path "$REPO_ROOT/.build/module-cache" \
    -o "$WORK_DIR/render-svg" \
    "$REPO_ROOT/scripts/render-svg.swift"

# One TIFF carrying both scales keeps the background sharp on Retina screens.
echo "Rendering DMG background ..."
"$WORK_DIR/render-svg" "$BACKGROUND_SVG" "$WORK_DIR/Background.png" 660 400
"$WORK_DIR/render-svg" "$BACKGROUND_SVG" "$WORK_DIR/Background@2x.png" 1320 800
/usr/bin/tiffutil -cathidpicheck \
    "$WORK_DIR/Background.png" \
    "$WORK_DIR/Background@2x.png" \
    -out "$WORK_DIR/Background.tiff" > /dev/null

mkdir -p "$(dirname "$OUT")"
"$DMGBUILD" \
    -s "$REPO_ROOT/scripts/dmg-settings.py" \
    -D "app=$APP" \
    -D "background=$WORK_DIR/Background.tiff" \
    "Network Sentinel" \
    "$OUT"

echo "Wrote $OUT"
