<p align="center">
  <img src="docs/assets/flick-icon.png" width="96" height="96" alt="Flick app icon">
</p>

<h1 align="center">Flick</h1>

<p align="center">A macOS window switcher with previews.</p>

## Install

Flick runs on Apple silicon and Intel Macs with macOS 14 or later.

1. Open the [latest Flick release](https://github.com/boleg-dev/Flick/releases/latest) and download the `.dmg` under **Assets**.
2. Open the disk image, drag **Flick** to **Applications**, then open Flick from there.
3. Follow Flick’s setup prompts. Allow **Accessibility** so Flick can handle the shortcut and focus the window you choose. Allow **Screen Recording** if you want window previews. Flick uses app icons when that permission is off. Reopen Flick if macOS asks.

Hold **Option**, press **Tab** until the window you want is highlighted, then release **Option** to switch. If another app uses Option + Tab, quit it to avoid shortcut conflicts.

## Features

- Switch between individual windows on your current desktop, including multiple windows from the same app. Minimized windows and hidden apps are excluded.
- Hold **Option** and press **backtick** to cycle through just the current app’s windows.
- Choose **Open at Login** in Flick’s menu to have it ready when you sign in.

### Window size and position

Enable **Show Window Size & Position** in Flick’s menu to show each window’s relative size and location on its display. Otherwise, the image fills the preview card.

<img src="docs/assets/window-placement.png" width="744" alt="Preview examples: filled card, small window at top left, small window at bottom right, and full-screen window.">

*Rendered examples using sample window content.*

### Controls

| Action | Control |
| --- | --- |
| Cycle through windows | Hold **Option**, press **Tab** |
| Cycle backward | Add **Shift** |
| Cycle within the current app | Hold **Option**, press **backtick** |
| Change selection | **Left / Right arrows**, scroll, or hover a card |
| Switch to selection | Release **Option**, press **Return**, or click |
| Cancel | **Escape** or click outside |

## Support

[Buy me a coffee](https://buymeacoffee.com/boleg)

## For developers

### Build from source

Install Xcode Command Line Tools with `xcode-select --install` if needed. Building requires Swift 5.9 or later. From the repository folder, run:

```sh
./build.sh
open Flick.app
```

### Build a release DMG

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

### Publish from your Mac

For each new release, update the version in `Info.plist`, commit the changes,
and push the commit to `origin/main`. With GitHub CLI authenticated for the
repository, run:

```sh
./Scripts/release.sh --publish
```

This runs the tests, builds and notarizes the DMG with your Mac’s Keychain,
then creates the version tag and GitHub Release and verifies the uploaded
DMG’s SHA-256. Use a clean checkout and let the command create the tag. Pushing the tag yourself
starts the hosted signing workflow. Local publishing needs no GitHub signing
secrets. Running the script without arguments just builds the verified DMG.

### Publish from GitHub Actions

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
