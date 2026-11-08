#!/bin/bash
# Builds BarTidy.app on macOS (needs Xcode command line tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

APP="BarTidy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/BarTidy" main.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>BarTidy</string>
  <key>CFBundleIdentifier</key><string>com.krishna.bartidy</string>
  <key>CFBundleName</key><string>BarTidy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"   # ad-hoc sign so macOS will run it
echo "Built $APP. Run: open $APP"
