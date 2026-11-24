#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
tag="v$version"
commit=$(git rev-parse HEAD)

check_release_source() {
  local changes current tagged
  changes=$(git status --porcelain --untracked-files=all) || return 1
  current=$(git rev-parse HEAD) || return 1
  if [[ -n "$changes" || "$current" != "$commit" ]]; then
    echo "Release builds require a clean working tree at the selected commit." >&2
    return 1
  fi
  if tagged=$(git rev-parse --verify --quiet "refs/tags/$tag^{commit}"); then
    if [[ "$tagged" != "$commit" ]]; then
      echo "$tag points to a different commit." >&2
      return 1
    fi
  else
    echo "Release builds require HEAD to be tagged $tag." >&2
    return 1
  fi
}

check_release_source

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

check_release_source
echo "Submitting $candidate"
xcrun notarytool submit "$candidate" "${notary_auth[@]}" --output-format plist > "$work/submission.plist"
submission_id=$(/usr/libexec/PlistBuddy -c 'Print id' "$work/submission.plist")
echo "Waiting for Apple notarization: $submission_id"
wait_result=0
xcrun notarytool wait "$submission_id" "${notary_auth[@]}" --output-format plist > "$work/result.plist" || wait_result=$?
status=$(/usr/libexec/PlistBuddy -c 'Print status' "$work/result.plist" 2>/dev/null) || status=unknown
if [[ $wait_result -ne 0 || "$status" != Accepted ]]; then
  echo "Notarization did not complete successfully (submission $submission_id, status $status)." >&2
  xcrun notarytool log "$submission_id" "${notary_auth[@]}" >&2 || echo "Apple's log is unavailable for submission $submission_id." >&2
  exit 1
fi
xcrun stapler staple "$candidate"
xcrun stapler validate "$candidate"
spctl --assess --type open --context context:primary-signature "$candidate"
mv -f "$candidate" "dist/$dmg"
echo "Ready to upload: dist/$dmg"
