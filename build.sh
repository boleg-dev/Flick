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

output_dir="${FLICK_BUILD_DIR:-.}"
swift Scripts/make-icon.swift "$output_dir/Resources"
swift build -c release "$@"
bin_dir=$(swift build -c release "$@" --show-bin-path)

APP="$output_dir/Flick.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$bin_dir/Flick" "$APP/Contents/MacOS/Flick"
plist="$APP/Contents/Info.plist"
cp Info.plist "$plist"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")
cp "$output_dir/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$IDENTITY" --identifier "$bundle_id" "${SIGNING_OPTIONS[@]}" \
  "$APP/Contents/MacOS/Flick"
codesign --force --sign "$IDENTITY" --identifier "$bundle_id" "${SIGNING_OPTIONS[@]}" \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Built $APP (signing identity: $IDENTITY)"
