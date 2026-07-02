#!/bin/bash
set -e

# Configuration
APP_NAME="Itsypin"
VERSION=$(grep 'MARKETING_VERSION:' project.yml | sed 's/.*: *"\(.*\)"/\1/')
SIGNING_IDENTITY="Developer ID Application: Nikolajs Ustinovs (R892A93W42)"

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/itsypin.xcarchive"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

cd "$PROJECT_DIR"
mkdir -p "$DIST_DIR"

echo "==> Version: $VERSION"

# Generate Xcode project from project.yml
echo "==> Generating Xcode project..."
xcodegen generate

# Archive without signing, then sign manually with Developer ID
echo "==> Archiving..."
xcodebuild -scheme itsypin -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

echo "==> Checking architectures..."
lipo -info "$ARCHIVE_APP/Contents/MacOS/$APP_NAME"

echo "==> Signing with Developer ID..."
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    --entitlements "$PROJECT_DIR/Sources/itsypin-direct.entitlements" \
    "$ARCHIVE_APP"

echo "==> Extracting app bundle..."
rm -rf "$APP_BUNDLE"
cp -R "$ARCHIVE_APP" "$APP_BUNDLE"
rm -rf "$ARCHIVE_PATH"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=1 "$APP_BUNDLE"

# Create DMG
echo "==> Creating DMG..."
rm -f "$DMG_PATH"
DMG_STAGING="$DIST_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo "==> Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)

echo ""
echo "==> Build complete!"
echo "    App: $APP_BUNDLE"
echo "    DMG: $DMG_PATH"
echo "    SHA256: $SHA256"
echo ""
echo "To notarize, run:"
echo "    xcrun notarytool submit \"$DMG_PATH\" --apple-id <APPLE_ID> --team-id R892A93W42 --password <APP_SPECIFIC_PASSWORD> --wait"
echo "    xcrun stapler staple \"$DMG_PATH\""
echo ""
echo "To create a GitHub release:"
echo "    gh release create v$VERSION \"$DMG_PATH\" --title \"v$VERSION\" --generate-notes"
echo ""
echo "For the App Store: open the project in Xcode, select the itsypin-appstore"
echo "scheme, then Product > Archive and upload via the Organizer."
