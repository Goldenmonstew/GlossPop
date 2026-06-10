#!/usr/bin/env bash
set -euo pipefail

# GlossPop release pipeline: archive → Developer ID sign → notarize → staple → DMG →
# Sparkle EdDSA sign + appcast. Run from the repo root. Prerequisites:
#   1. A "Developer ID Application" certificate in your login keychain
#      (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application).
#   2. An App Store Connect API key (.p8) for notarytool (set ASC_KEY_ID / ASC_ISSUER below).
#   3. The Sparkle EdDSA private key in your keychain (Sparkle's bin/generate_keys, run once).

# ---- config ----
SCHEME="GlossPop"
PROJECT="GlossPop.xcodeproj"
APP_NAME="GlossPop"
TEAM_ID="${TEAM_ID:?set your Apple Developer Team ID}"
GITHUB_OWNER="${GITHUB_OWNER:-yourname}"   # owner of the releases repo
GITHUB_REPO="GlossPop"

# App Store Connect API key for notarytool (Admin key per project convention):
ASC_KEY_ID="${ASC_KEY_ID:?set your App Store Connect API key id}"
ASC_ISSUER="${ASC_ISSUER:?set your ASC issuer id}"
ASC_KEY_PATH="$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8"

BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/$APP_NAME.app"
DIST_DIR="dist"
SPARKLE_BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"

VERSION=$(awk -F'"' '/MARKETING_VERSION:/{print $2; exit}' project.yml)
[ -n "$VERSION" ] || { echo "✗ could not read MARKETING_VERSION from project.yml"; exit 1; }
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
DL_PREFIX="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/download/v$VERSION/"

# ---- preflight ----
DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
[ -n "$DEVELOPER_ID" ] || { echo "✗ No 'Developer ID Application' cert in keychain (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates)."; exit 1; }
[ -f "$ASC_KEY_PATH" ] || { echo "✗ ASC API key not found at $ASC_KEY_PATH"; exit 1; }
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "✗ Sparkle tools missing — run a build first to resolve SPM."; exit 1; }
echo "▶ signing as: $DEVELOPER_ID  ·  version: $VERSION"

# ---- archive ----
echo "▶ archive"
rm -rf "$ARCHIVE"
xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE" -destination 'generic/platform=macOS' \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="$DEVELOPER_ID" CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"

# ---- export Developer ID app ----
echo "▶ export"
mkdir -p "$BUILD_DIR"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
</dict></plist>
PLIST
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"
codesign --verify --deep --strict --verbose=2 "$APP"

# ---- DMG ----
echo "▶ build DMG"
mkdir -p "$DIST_DIR"; rm -f "$DMG"
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG"

# ---- notarize + staple ----
echo "▶ notarize (a few minutes)…"
xcrun notarytool submit "$DMG" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" --wait
echo "▶ staple"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# ---- Sparkle: sign DMG + (re)generate appcast ----
echo "▶ Sparkle appcast (signs DMG with the EdDSA key in your keychain)"
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "$DL_PREFIX" "$DIST_DIR"
cp "$DIST_DIR/appcast.xml" ./appcast.xml   # served from repo root → matches SUFeedURL in project.yml

echo "✓ done — artifacts:"
ls -1 "$DIST_DIR"; echo "  ./appcast.xml"
cat <<NEXT

Next steps (GitHub Releases hosting):
  1. Tag + create a GitHub Release  v$VERSION  on $GITHUB_OWNER/$GITHUB_REPO
  2. Upload  $DMG  as a release asset
  3. Commit  ./appcast.xml  so SUFeedURL serves it:
       https://raw.githubusercontent.com/$GITHUB_OWNER/$GITHUB_REPO/main/appcast.xml
     (this is the SUFeedURL baked into project.yml → Info.plist)
NEXT
