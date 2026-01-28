#!/bin/bash
set -e

# Configuration
APP_NAME="Pinster"
BUNDLE_ID="com.pinster.app"
TEAM_ID="R892A93W42"
VERSION="1.0.2"

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/dist/$APP_NAME.app"
DMG_PATH="$PROJECT_DIR/dist/$APP_NAME-$VERSION.dmg"

cd "$PROJECT_DIR"

echo "==> Building release binary for arm64..."
swift build -c release --arch arm64

echo "==> Building release binary for x86_64..."
swift build -c release --arch x86_64

echo "==> Creating universal binary..."
mkdir -p "$BUILD_DIR"
lipo -create \
    "$PROJECT_DIR/.build/arm64-apple-macosx/release/pinster" \
    "$PROJECT_DIR/.build/x86_64-apple-macosx/release/pinster" \
    -output "$BUILD_DIR/pinster"

echo "==> Creating app bundle..."
rm -rf dist
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/pinster" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy icons
cp "Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
cp "Assets/MenuBarIcon.png" "$APP_BUNDLE/Contents/Resources/"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

# Check if we should sign
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')"

    echo "==> Signing app with: $SIGNING_IDENTITY"
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
        --entitlements "$PROJECT_DIR/Sources/pinster.entitlements" \
        "$APP_BUNDLE"

    echo "==> Creating DMG..."
    hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

    echo "==> Signing DMG..."
    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

    echo ""
    echo "==> Build complete!"
    echo "    App: $APP_BUNDLE"
    echo "    DMG: $DMG_PATH"
    echo ""
    echo "To notarize, run:"
    echo "    xcrun notarytool submit \"$DMG_PATH\" --apple-id YOUR_APPLE_ID --team-id $TEAM_ID --password APP_SPECIFIC_PASSWORD --wait"
    echo "    xcrun stapler staple \"$DMG_PATH\""
else
    echo "==> No Developer ID certificate found, skipping signing..."

    echo "==> Creating unsigned DMG..."
    hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

    echo ""
    echo "==> Build complete (UNSIGNED)!"
    echo "    App: $APP_BUNDLE"
    echo "    DMG: $DMG_PATH"
    echo ""
    echo "NOTE: To distribute, you need a Developer ID certificate from developer.apple.com"
fi
