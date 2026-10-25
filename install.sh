#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

SOURCE="dist/Headroom.app"
DEST="/Applications/Headroom.app"
APPEX="$DEST/Contents/PlugIns/AIUsageWidget.appex"
OLD_APP="/Applications/AI Usage Widget.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ ! -d "$SOURCE" ]; then
    echo "Run ./build.sh first."
    exit 1
fi

pkill -f "$DEST/Contents/MacOS/AIUsageWidget" 2>/dev/null || true
pkill -f "$SOURCE/Contents/MacOS/AIUsageWidget" 2>/dev/null || true
pkill -f "$OLD_APP/Contents/MacOS/AIUsageWidget" 2>/dev/null || true
sleep 0.4

# Remove the previous product name so only one bundle with this identifier exists.
if [ -d "$OLD_APP" ]; then
    pluginkit -r "$OLD_APP/Contents/PlugIns/AIUsageWidget.appex" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$OLD_APP" >/dev/null 2>&1 || true
    rm -rf "$OLD_APP"
fi

rm -rf "$DEST"
mv "$SOURCE" "$DEST"
codesign --verify --deep --strict "$DEST"

"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

for attempt in 1 2 3 4; do
    pluginkit -a "$APPEX" >/dev/null 2>&1 || true
    if pluginkit -m -i com.drafff.aiusagewidget.widget >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

open "$DEST"

if [ -f "$HOME/Library/LaunchAgents/com.drafff.aiusagewidget.plist" ]; then
    ./autostart.sh install >/dev/null 2>&1 || true
fi

# chronod keeps the previous extension session until restarted; reload it so
# the installed build is used immediately.
killall chronod 2>/dev/null || true

echo "Installed: $DEST"
