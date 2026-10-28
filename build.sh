#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"
TARGET="arm64-apple-macos14.0"
BUILD="build"
APP="dist/Headroom.app"
APPEX="$APP/Contents/PlugIns/AIUsageWidget.appex"

mkdir -p "$BUILD"

echo "Compiling host…"
swiftc -O -target "$TARGET" -sdk "$SDK" \
    Sources/UsageCore/*.swift Sources/AIUsageWidget/*.swift \
    -o "$BUILD/AIUsageWidget" \
    -framework AppKit -framework SwiftUI -framework WidgetKit

echo "Compiling widget extension…"
swiftc -O -parse-as-library -target "$TARGET" -sdk "$SDK" \
    Sources/UsageCore/*.swift Sources/WidgetExtension/WidgetMain.swift \
    -o "$BUILD/AIUsageWidgetExtension" \
    -framework WidgetKit -framework SwiftUI \
    -Xlinker -e -Xlinker _NSExtensionMain

echo "Rendering icon…"
"$BUILD/AIUsageWidget" --icon "$BUILD/AppIcon-1024.png" >/dev/null
rm -rf "$BUILD/AppIcon.iconset"
mkdir -p "$BUILD/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$BUILD/AppIcon-1024.png" \
        --out "$BUILD/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$BUILD/AppIcon-1024.png" \
        --out "$BUILD/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

echo "Packaging…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"
cp "$BUILD/AIUsageWidget" "$APP/Contents/MacOS/AIUsageWidget"
cp "$BUILD/AIUsageWidgetExtension" "$APPEX/Contents/MacOS/AIUsageWidgetExtension"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Headroom</string>
    <key>CFBundleDisplayName</key>
    <string>Headroom</string>
    <key>CFBundleIdentifier</key>
    <string>com.drafff.aiusagewidget</string>
    <key>CFBundleExecutable</key>
    <string>AIUsageWidget</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.1</string>
    <key>CFBundleVersion</key>
    <string>__BUILD__</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

cat > "$APPEX/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AIUsageWidgetExtension</string>
    <key>CFBundleDisplayName</key>
    <string>Headroom</string>
    <key>CFBundleIdentifier</key>
    <string>com.drafff.aiusagewidget.widget</string>
    <key>CFBundleExecutable</key>
    <string>AIUsageWidgetExtension</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.1</string>
    <key>CFBundleVersion</key>
    <string>__BUILD__</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleSupportedPlatforms</key>
    <array><string>MacOSX</string></array>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

BUILD_NUMBER="$(date +%Y%m%d%H%M)"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APPEX/Contents/Info.plist"

echo "Signing…"
SIGN_ID="${AIUSAGE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_ID" ]; then
    SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:|Developer ID Application:/ {print $2; exit}')"
fi
if [ -z "$SIGN_ID" ]; then
    SIGN_ID="-"
    echo "WARNING: no Apple Development identity found."
    echo "         Signing ad-hoc. macOS 26 (amfid) will reject this widget extension, so it will not appear in the gallery."
    echo "         Install Xcode, sign in with an Apple ID (free), then re-run this script."
fi
codesign --force --sign "$SIGN_ID" --entitlements Resources/widget.entitlements "$APPEX"
codesign --force --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict "$APP"
TEAM="$(codesign -dv --verbose=4 "$APPEX" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [ -n "$TEAM" ] && [ "$TEAM" != "not set" ]; then
    echo "Signed with team $TEAM — WidgetKit will accept the extension."
fi

echo "Registering…"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
pluginkit -a "$APPEX" >/dev/null 2>&1 || true

echo "Built: $APP"
echo "Run:   open \"$APP\""
