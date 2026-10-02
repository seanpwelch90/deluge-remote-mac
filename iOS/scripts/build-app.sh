#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode is required to build the iOS app." >&2
  exit 1
fi

xcodebuild \
  -project "Deluge Remote.xcodeproj" \
  -scheme "Deluge Remote" \
  -destination "generic/platform=iOS Simulator" \
  -configuration Release \
  -derivedDataPath "build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$(find "build/DerivedData/Build/Products/Release-iphonesimulator" -name "Deluge Remote.app" -print -quit)"
if [[ -z "$APP" ]]; then
  echo "The simulator app was not produced." >&2
  exit 1
fi

rm -rf "build/Deluge Remote.app"
cp -R "$APP" "build/Deluge Remote.app"
echo "Built $(pwd)/build/Deluge Remote.app"
