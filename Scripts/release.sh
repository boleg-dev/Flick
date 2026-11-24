#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

notary_auth=(--keychain-profile "${NOTARY_PROFILE:-DeveloperID-Notary}")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
  notary_auth+=(--keychain "$NOTARY_KEYCHAIN")
fi
identity=${SIGNING_IDENTITY:-}
if [[ -z "$identity" ]]; then
  identities=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p')
  if [[ -z "$identities" || "$identities" == *$'\n'* ]]; then
    echo "Select a valid Developer ID Application certificate with SIGNING_IDENTITY." >&2
    exit 1
  fi
  identity=$identities
fi
if [[ "$identity" != "Developer ID Application: "* ]]; then
  echo "A release requires a Developer ID Application certificate." >&2
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
mkdir -p dist
work=$(mktemp -d dist/.release.XXXXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir "$work/image"
FLICK_BUILD_DIR="$work" SIGNING_IDENTITY="$identity" ./build.sh --arch arm64 --arch x86_64
for arch in arm64 x86_64; do
  lipo "$work/Flick.app/Contents/MacOS/Flick" -verify_arch "$arch"
done
mv "$work/Flick.app" "$work/image/"
ln -s /Applications "$work/image/Applications"

dmg="Flick-$version.dmg"
candidate="$work/$dmg"
hdiutil create -volname Flick -srcfolder "$work/image" -format UDZO "$candidate"
codesign --force --sign "$identity" --timestamp "$candidate"
codesign --verify --strict "$candidate"
hdiutil verify "$candidate"

# Preserve the exact submitted file so an interrupted request can be resumed.
mkdir -p dist/pending
pending=$(mktemp -d dist/pending/submission.XXXXXXXX)
mv "$candidate" "$pending/$dmg"
candidate="$pending/$dmg"
echo "Submitting $candidate"
xcrun notarytool submit "$candidate" "${notary_auth[@]}" --wait --output-format plist > "$pending/result.plist"
status=$(/usr/libexec/PlistBuddy -c 'Print status' "$pending/result.plist")
if [[ "$status" != Accepted ]]; then
  cat "$pending/result.plist" >&2
  exit 1
fi
xcrun stapler staple "$candidate"
xcrun stapler validate "$candidate"
spctl --assess --type open --context context:primary-signature "$candidate"
mv -f "$candidate" "dist/$dmg"
echo "Ready to upload: dist/$dmg"
