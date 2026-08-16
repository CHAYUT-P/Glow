#!/bin/bash
# Builds a release Glow.app bundle from the SVG icon and installs it.
#   ./Scripts/make-app.sh            build + install to /Applications
#   GLOW_APP_DIR=~/Applications ./Scripts/make-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_DIR="${GLOW_APP_DIR:-/Applications}"
BUILD_DIR="build"
APP="$BUILD_DIR/Glow.app"
ICON_SVG="Design/glow-icon-d.svg"

echo "== Building release binary"
swift build -c release
BIN=$(find .build -path '*/release/Glow' -type f | head -1)
[ -n "$BIN" ] || { echo "release binary not found"; exit 1; }

echo "== Rendering icon ($ICON_SVG)"
rm -rf "$BUILD_DIR/AppIcon.iconset"
mkdir -p "$BUILD_DIR/AppIcon.iconset"
swift Scripts/svg-to-png.swift "$ICON_SVG" "$BUILD_DIR/icon-master.png" 1024 >/dev/null
M="$BUILD_DIR/icon-master.png"
while read -r px name; do
    sips -z "$px" "$px" "$M" --out "$BUILD_DIR/AppIcon.iconset/$name.png" >/dev/null
done <<'SIZES'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
SIZES
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"

echo "== Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Glow"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Glow</string>
    <key>CFBundleDisplayName</key><string>Glow</string>
    <key>CFBundleExecutable</key><string>Glow</string>
    <key>CFBundleIdentifier</key><string>local.glow</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "== Installing to $APP_DIR"
pkill -x Glow 2>/dev/null || true
rm -rf "$APP_DIR/Glow.app"
if ! cp -R "$APP" "$APP_DIR/" 2>/dev/null; then
    echo "No write access to $APP_DIR, falling back to ~/Applications"
    APP_DIR="$HOME/Applications"
    mkdir -p "$APP_DIR"
    cp -R "$APP" "$APP_DIR/"
fi
echo "Installed: $APP_DIR/Glow.app"
echo "Open it with: open '$APP_DIR/Glow.app'"
