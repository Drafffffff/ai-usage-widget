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
mv "$SOURCE" "$DEST"
codesign --verify --deep --strict "$DEST"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

for attempt in 1 2 3 4; do
    pluginkit -a "$APPEX" >/dev/null 2>&1 || true
    if pluginkit -m -i com.drafff.aiusagewidget.widget >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

open "$DEST"
echo "Installed: $DEST"
