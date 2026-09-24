#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! swift --version >/dev/null 2>&1; then
  if [[ -x /Library/Developer/CommandLineTools/usr/bin/swift ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  else
    echo "Swift is unavailable. Install Xcode or the Command Line Tools and accept the Xcode license." >&2
    exit 1
  fi
fi

SWIFT_ARGS=()
DEV_ROOT="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
if [[ -n "$DEV_ROOT" ]] && ! find "$DEV_ROOT" -name libSwiftUIMacros.dylib -print -quit 2>/dev/null | grep -q .; then
  PLUGIN="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
  if [[ ! -d "$PLUGIN" ]]; then
    echo "SwiftUI build tools were not found. Install Xcode, then run this script again." >&2
    exit 1
  fi
  SWIFT_ARGS=(-Xswiftc -plugin-path -Xswiftc "$PLUGIN")
fi

if [[ ${#SWIFT_ARGS[@]} -eq 0 ]]; then
  swift build -c release
else
  swift build -c release "${SWIFT_ARGS[@]}"
fi

ICON_DIR="$(mktemp -d)"
swift scripts/make-icon.swift "Support/AppIcon.icon" "$ICON_DIR/icon_512x512@2x.png"
mkdir -p "$ICON_DIR/AppIcon.iconset"
cp "$ICON_DIR/icon_512x512@2x.png" "$ICON_DIR/AppIcon.iconset/icon_512x512@2x.png"
sips -z 16 16 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/AppIcon.iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/AppIcon.iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/AppIcon.iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/AppIcon.iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/AppIcon.iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/AppIcon.iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/AppIcon.iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/AppIcon.iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/AppIcon.iconset/icon_512x512.png" >/dev/null
iconutil -c icns "$ICON_DIR/AppIcon.iconset" -o "$ICON_DIR/AppIcon.icns"

APP="build/Deluge Remote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/DelugeRemote" "$APP/Contents/MacOS/DelugeRemote"
cp "Support/Info.plist" "$APP/Contents/Info.plist"
cp "$ICON_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_DIR"
chmod +x "$APP/Contents/MacOS/DelugeRemote"
codesign --force --sign - "$APP"

echo "Built $(pwd)/$APP"
