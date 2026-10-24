#!/bin/bash
set -euo pipefail

LABEL="com.drafff.aiusagewidget"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="${AIUSAGE_APP_PATH:-/Applications/AI Usage Widget.app}"
ACTION="${1:-status}"

case "$ACTION" in
    install)
        if [ ! -d "$APP" ]; then
            echo "App not found at $APP. Run ./install.sh first."
            exit 1
        fi
        mkdir -p "$HOME/Library/LaunchAgents"
        cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$APP</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLIST
        launchctl bootout "gui/$UID" "$PLIST" 2>/dev/null || true
        launchctl bootstrap "gui/$UID" "$PLIST"
        echo "Autostart enabled (login item: $LABEL)"
        ;;
    remove)
        launchctl bootout "gui/$UID" "$PLIST" 2>/dev/null || true
        rm -f "$PLIST"
        echo "Autostart disabled"
        ;;
    status)
        if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
            echo "enabled"
        else
            echo "disabled"
        fi
        ;;
    *)
        echo "Usage: $0 [install|remove|status]"
        exit 1
        ;;
esac
