#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

SOURCE="dist/AI Usage Widget.app"
DEST="/Applications/AI Usage Widget.app"
APPEX="$DEST/Contents/PlugIns/AIUsageWidget.appex"

if [ ! -d "$SOURCE" ]; then
    echo "Run ./build.sh first."
    exit 1
fi

pkill -f "$DEST/Contents/MacOS/AIUsageWidget" 2>/dev/null || true
pkill -f "$SOURCE/Contents/MacOS/AIUsageWidget" 2>/dev/null || true
sleep 0.4

rm -rf "$DEST"
ditto "$SOURCE" "$DEST"
codesign --verify --deep --strict "$DEST"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

pluginkit -r "$SOURCE/Contents/PlugIns/AIUsageWidget.appex" >/dev/null 2>&1 || true
pluginkit -a "$APPEX" >/dev/null 2>&1 || true

open "$DEST"
echo "Installed: $DEST"
