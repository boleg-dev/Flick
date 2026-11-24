# Releasing Flick

This guide is for maintainers publishing official Flick releases. Publishing requires write access to the repository. Signing and notarization require a Developer ID Application signing identity and Apple notarization credentials. Configuring the GitHub release environment requires repository admin access.

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
DMG’s SHA-256. Use a clean checkout and let the command create the tag. Pushing the tag yourself
starts the hosted signing workflow. Local publishing needs no GitHub signing
secrets. Running the script without arguments just builds the verified DMG.

## Publish from GitHub Actions

Create a GitHub Actions environment named `release` and add these secrets:

| Secret | Value |
| --- | --- |
| `CERTIFICATE_P12_BASE64` | Base64 of the password-protected Developer ID Application certificate and private key exported together as a .p12 from Keychain Access |
| `CERTIFICATE_PASSWORD` | Password used for that export |
| `NOTARY_PRIVATE_KEY` | Full text of the App Store Connect team API key (.p8), including its header, footer, and line breaks |
| `NOTARY_KEY_ID` | Key ID shown for that key |
| `NOTARY_ISSUER_ID` | Issuer ID from the Team Keys page |

On macOS, `base64 -i /path/to/signing.p12 | pbcopy` copies the encoded certificate
for the secret. Store both private key files outside the checkout. Restrict who can
push release tags or access the release environment.

Push a tag matching the version in `Info.plist` (for example, `v1.0` for version
`1.0`). The workflow runs the tests, signs and notarizes the universal DMG, and
publishes a GitHub Release with the verified disk image attached.
