<p align="center">
  <img src="docs/assets/flick-icon.png" width="96" height="96" alt="Flick app icon">
</p>

<h1 align="center">Flick</h1>

<p align="center">A macOS window switcher with previews.</p>

## Build and run

Requires macOS 14+ and Swift 5.9+. Install Xcode Command Line Tools with `xcode-select --install` if needed.

From the repository folder:

```sh
./build.sh
open Flick.app
```

Move `Flick.app` to Applications to keep it installed. **Open at Login** is available in Flick’s menu.

## Setup

Grant **Accessibility** permission for shortcuts and window switching, and **Screen Recording** for previews. Without screen access, Flick shows app icons. Reopen Flick if macOS requests it.

Quit other apps using Option + Tab to avoid shortcut conflicts.

## Controls

| Action | Control |
| --- | --- |
| Cycle through windows | Hold **Option**, press **Tab** |
| Cycle backward | Add **Shift** |
| Cycle within the current app | Hold **Option**, press **backtick** (`) |
| Change selection | **Left / Right arrows**, scroll, or hover a card |
| Switch to selection | Release **Option**, press **Return**, or click |
| Cancel | **Escape** or click outside |

Flick lists on-screen windows on the current desktop, excluding minimized windows and hidden apps.

## Window size and position

Enable **Show Window Size & Position** in Flick’s menu to show each window’s relative size and location on its display. Otherwise, the image fills the preview card.

<img src="docs/assets/window-placement.png" width="744" alt="Preview examples: filled card, small window at top left, small window at bottom right, and full-screen window.">

*Rendered examples using sample window content.*

## Support

[Buy me a coffee](https://buymeacoffee.com/boleg)
