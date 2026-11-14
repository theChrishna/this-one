#!/bin/bash
# Builds, signs, notarizes and staples "BarTidy Plus.app", then zips it for sharing.
#
# One-time setup (needs a paid Apple Developer account):
#   1. Create a "Developer ID Application" certificate (Xcode › Settings › Accounts › Manage Certificates).
#   2. Make an app-specific password at https://account.apple.com and store it:
#        xcrun notarytool store-credentials bartidy --apple-id you@example.com --team-id TEAMID
#
# Then:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" tools/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity (security find-identity -v -p codesigning)}"
PROFILE="${NOTARY_PROFILE:-bartidy}"

./build.sh
APP="build.noindex/BarTidy Plus.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"

ditto -c -k --keepParent "$APP" BarTidyPlus-upload.zip
xcrun notarytool submit BarTidyPlus-upload.zip --keychain-profile "$PROFILE" --wait
rm BarTidyPlus-upload.zip

xcrun stapler staple "$APP"
spctl --assess --type execute -vv "$APP"

ditto -c -k --keepParent "$APP" "BarTidyPlus-$VERSION.zip"
echo "Ready to share: BarTidyPlus-$VERSION.zip"
