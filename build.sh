#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${SIGNING_IDENTITY:--}"
SIGNING_OPTIONS=(--options runtime)
if [[ "$IDENTITY" != "-" ]]; then
  if security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""; then
    SIGNING_OPTIONS+=(--timestamp)
  else
    echo "Signing identity not found: $IDENTITY" >&2
    exit 1
  fi
fi

swift Scripts/make-icon.swift Resources
swift build -c release

APP="Flick.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Flick "$APP/Contents/MacOS/Flick"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$IDENTITY" --identifier "dev.oleg.flick" "${SIGNING_OPTIONS[@]}" \
  "$APP/Contents/MacOS/Flick"
codesign --force --sign "$IDENTITY" --identifier "dev.oleg.flick" "${SIGNING_OPTIONS[@]}" \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Built $APP (signing identity: $IDENTITY)"
