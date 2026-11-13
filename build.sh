#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift Scripts/make-icon.swift Resources
swift build -c release

APP="Flick.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Flick "$APP/Contents/MacOS/Flick"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="-"
if ! security find-identity -v -p codesigning | grep -Fq "$IDENTITY"; then
  IDENTITY="-"
fi

codesign --force --sign "$IDENTITY" --identifier "dev.oleg.flick" --options runtime \
  "$APP/Contents/MacOS/Flick"
codesign --force --sign "$IDENTITY" --identifier "dev.oleg.flick" --options runtime \
  "$APP"

echo "Built $APP"
