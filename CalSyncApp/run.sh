#!/bin/bash
# Build and launch CalSyncApp as a proper macOS app bundle.
# Swift Package Manager produces a raw binary; MenuBarExtra requires a bundle.

set -e

PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PACKAGE_DIR/.build/debug"
APP_BUNDLE="$BUILD_DIR/CalSyncApp.app"
BINARY_NAME="CalSyncApp"

echo "Building..."
swift build --package-path "$PACKAGE_DIR" 2>&1

# Create minimal app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$BINARY_NAME" "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CalSyncApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.calsync.app</string>
    <key>CFBundleName</key>
    <string>CalSync</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>CalSync needs access to your calendars to sync events.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "Signing..."
# Ad-hoc signing is required on macOS for GUI apps (MenuBarExtra) to claim menu bar space
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Launching CalSync..."
# Kill any existing instance
pkill -f "CalSyncApp.app/Contents/MacOS/CalSyncApp" 2>/dev/null || true
sleep 0.5

open "$APP_BUNDLE"
