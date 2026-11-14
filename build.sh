#!/bin/bash
# Builds BarTidy.app (universal: Apple silicon + Intel).
# Needs the Xcode command line tools: xcode-select --install
#
#   ./build.sh                     ad-hoc signed, for this Mac
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
#                                  signed for distribution (then run tools/notarize.sh)
set -euo pipefail
cd "$(dirname "$0")"

APP="BarTidy.app"
VERSION="2.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
MIN_MACOS="13.0"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find Sources/BarTidy -name '*.swift' | sort)
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos$MIN_MACOS" -module-name BarTidy -o "$TMP/BarTidy-$arch" "${SOURCES[@]}"
done
lipo -create "$TMP/BarTidy-arm64" "$TMP/BarTidy-x86_64" -output "$APP/Contents/MacOS/BarTidy"

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>BarTidy</string>
  <key>CFBundleIdentifier</key><string>com.krishna.bartidy</string>
  <key>CFBundleName</key><string>BarTidy</string>
  <key>CFBundleDisplayName</key><string>BarTidy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Krishna</string>
</dict>
</plist>
PLIST

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # Hardened runtime + secure timestamp are required for notarization.
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"   # ad-hoc: runs on this Mac only
fi
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION build $BUILD). Run: open $APP"
