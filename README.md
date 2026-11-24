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

<a href="https://buymeacoffee.com/boleg"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy me a coffee" width="150"></a>

## For developers

### Build from source

Install Xcode Command Line Tools with `xcode-select --install` if needed. Building requires Swift 5.9 or later. From the repository folder, run:

```sh
./build.sh
open Flick.app
```

Maintainers can follow the [release guide](docs/RELEASING.md) to sign and publish a DMG.
