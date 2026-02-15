#!/bin/bash
# Build and package Liuwa as a macOS .app bundle
set -euo pipefail

CONFIG="${1:-release}"
ARCH="${2:-arm64}"

echo "Building Liuwa ($CONFIG, $ARCH)..."
swift build -c "$CONFIG" --arch "$ARCH"

APP="Liuwa.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Copy binary
cp ".build/$CONFIG/Liuwa" "$APP/Contents/MacOS/Liuwa"

# Copy Info.plist
cp Sources/Liuwa/Info.plist "$APP/Contents/Info.plist"

# Add required plist keys if missing
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Liuwa" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP/Contents/Info.plist" 2>/dev/null || true

# Ad-hoc code sign
codesign --force --deep -s - "$APP"

echo "Created $APP (ad-hoc signed)"
