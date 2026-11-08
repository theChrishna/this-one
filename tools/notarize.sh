#!/bin/bash
# Builds, signs, notarizes and staples BarTidy.app, then zips it for sharing.
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
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' BarTidy.app/Contents/Info.plist)"

ditto -c -k --keepParent BarTidy.app BarTidy-upload.zip
xcrun notarytool submit BarTidy-upload.zip --keychain-profile "$PROFILE" --wait
rm BarTidy-upload.zip

xcrun stapler staple BarTidy.app
spctl --assess --type execute -vv BarTidy.app

ditto -c -k --keepParent BarTidy.app "BarTidy-$VERSION.zip"
echo "Ready to share: BarTidy-$VERSION.zip"
