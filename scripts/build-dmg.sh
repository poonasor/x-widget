#!/usr/bin/env bash
# Builds a Developer ID–signed, notarized DMG of X Widget into build/release/.
#
# One-time setup (stores notarization credentials in your keychain):
#   xcrun notarytool store-credentials x-widget-notary --apple-id <your Apple ID> --team-id RNUS5696SB
#
# Usage:
#   scripts/build-dmg.sh                    # sign + notarize (shareable)
#   SKIP_NOTARIZE=1 scripts/build-dmg.sh    # sign only (local testing)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="X Widget"
IDENTITY="Developer ID Application: perpetual media ltd. (RNUS5696SB)"
NOTARY_PROFILE="${NOTARY_PROFILE:-x-widget-notary}"
OUT=build/release

rm -rf "$OUT" && mkdir -p "$OUT"
command -v xcodegen >/dev/null && xcodegen generate --quiet

echo "▸ Archiving"
xcodebuild archive -quiet \
  -project XWidget.xcodeproj -scheme XWidget -configuration Release \
  -destination "generic/platform=macOS" -archivePath "$OUT/XWidget.xcarchive" -allowProvisioningUpdates

echo "▸ Exporting with Developer ID"
xcodebuild -exportArchive -quiet \
  -archivePath "$OUT/XWidget.xcarchive" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates

APP="$OUT/export/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
codesign --verify --deep --strict "$APP"

echo "▸ Creating DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target
DMG="$OUT/XWidget-$VERSION.dmg"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "⚠︎ Skipped notarization: other Macs will block this DMG."
else
  # Notarizing the DMG covers the app inside it; stapling lets Gatekeeper verify offline.
  echo "▸ Notarizing (usually a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple -q "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

echo "✓ $DMG"
