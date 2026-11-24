# Releasing Flick

This guide is for maintainers publishing official Flick releases. Publishing requires write access to the repository. Signing and notarization require a Developer ID Application signing identity and Apple notarization credentials.

## Build a release DMG

The build uses the numeric version in `Info.plist` for both the display version
and the packaged `CFBundleVersion`. Increase it with every release.

From a clean checkout at the matching version tag, save your notarization credentials in Keychain once using
`xcrun notarytool store-credentials DeveloperID-Notary`. Then run:

```sh
./Scripts/release.sh
```

The script builds for Apple silicon and Intel, signs with Developer ID, submits
the disk image to Apple, and staples and verifies the ticket. Upload the DMG
printed at the end to GitHub Releases. If you have multiple Developer ID
Application certificates, set `SIGNING_IDENTITY` to the certificate name.
Set `NOTARY_PROFILE` to use a different Keychain profile.

## Publish from your Mac

For each new release, update the version in `Info.plist`, commit the changes,
and get the commit onto the repository’s `main` branch. Check out that commit locally. With GitHub CLI authenticated for the
repository, run:

```sh
./Scripts/release.sh --publish
```

This runs the tests, builds and notarizes the DMG with your Mac’s Keychain,
then creates the version tag and GitHub Release and verifies the uploaded
DMG’s SHA-256. Use a clean checkout and let the command create the tag.
