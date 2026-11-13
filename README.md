<p align="center">
  <img src="docs/assets/flick-icon.png" width="96" height="96" alt="Flick app icon">
</p>

<h1 align="center">Flick</h1>

<p align="center">
  <strong>Find the window you meant to switch to.</strong><br>
  A small, native window switcher for macOS.
</p>

<p align="center">
  Option + Tab · Window previews · Optional screen positioning<br>
  No account. No subscription. No network requests.
</p>

---

Hold **Option**, press **Tab**, and release Option on the window you want. Flick shows individual windows with previews, so you can pick the right one when an app has several open.

Want to recognize a window by where you left it? Turn on **Show Window Size & Position**. A small window in the top-left corner stays small and top-left in its preview, instead of filling the card.

<p align="center">
  <img src="docs/assets/window-placement.png" width="744" alt="Four rendered examples: a filled preview with positioning off, a small window at the top left, a small window at the bottom right, and a full-screen window. With positioning on, each window appears inside a miniature screen.">
</p>

<p align="center"><sub>Rendered with Flick’s preview view and sample window content.</sub></p>

## What it does

- **Switch between windows.** See separate windows from the same app.
- **Stay within one app.** Use Option + backtick to cycle through its windows.
- **See where you left things.** Optional previews reflect each window’s size and position on its display.
- **Use the input that feels right.** Keyboard, mouse selection, and two-finger scrolling work while the switcher is open.
- **Keep out of the way.** Flick lives in the menu bar and can open at login.
- **Work locally.** Preview images stay in memory. No analytics, uploads, or account setup.

## Build and run

Flick currently builds from source. You’ll need **macOS 14 or later** and **Xcode Command Line Tools with Swift 5.9 or later**.

Clone or download this repository, open a terminal in its folder, then run:

```sh
./build.sh
open Flick.app
```

If the developer tools aren’t installed:

```sh
xcode-select --install
```

The build script generates the icon, compiles the app, and creates `Flick.app`. It uses the author’s development signing identity when available and falls back to ad-hoc signing on other Macs; you don’t need your own signing certificate to build it locally.

Move `Flick.app` to **Applications** if you want to keep it installed. Enable **Open at Login** from Flick’s menu to launch it when you sign in.

> Quit AltTab or any other app using Option + Tab before trying Flick, so the two apps don’t compete for the shortcut.

## First launch

Flick uses two macOS permissions:

| Permission | What it enables |
| --- | --- |
| **Accessibility** | The global keyboard shortcut and focusing the window you choose. |
| **Screen Recording** | Window thumbnails. Switching still works without it, using app icons. |

Grant them from Flick’s setup window or **System Settings → Privacy & Security**. If macOS asks you to quit and reopen Flick, do so.

macOS may also ask to let Flick **“bypass the system private window picker.”** That is the direct-capture confirmation used to obtain thumbnails without selecting each window through Apple’s picker. It can appear even when Screen Recording is already enabled.

The system dialog mentions screen and audio access. Flick captures **still window images only**; it does not record audio or video, save captures to disk, or send them anywhere.

## Controls

| Action | Control |
| --- | --- |
| Open the switcher and move forward | Hold **Option**, press **Tab** |
| Move backward | Hold **Option + Shift**, press **Tab** |
| Switch within the current app | Hold **Option**, press **backtick** (`) |
| Move through the open switcher | **Left / Right arrows** or **two-finger scroll** |
| Select with the pointer | Move over a window’s card |
| Switch to the selection | Release **Option**, press **Return**, or **click** the card |
| Cancel without switching | **Escape** or click outside the switcher |
| Open without the shortcut | Flick menu → **Show Windows** |

## Show size and position

Choose **Show Window Size & Position** from Flick’s menu.

- **Off:** the window image fills its preview card.
- **On:** a miniature screen shows the window at its relative size and position.

The setting is off by default, remembered across restarts, and applied the next time you open the switcher. For a window spanning displays, Flick uses the display containing the largest portion of it and clips the overflow. This mode uses the same capture permission as ordinary previews.

## Current scope

Flick lists on-screen windows on the current desktop. It does not bring in minimized windows, hidden apps, or windows on other Spaces. If the current app has no eligible windows, the current-app shortcut falls back to the full list.

This is an early project. Automated checks cover session timing, preview cancellation, and placement geometry; real multi-display setups still need broader hands-on testing.

<details>
<summary><strong>Troubleshooting</strong></summary>

### The shortcut does nothing

Check Accessibility permission, quit other window switchers, and restart Flick. Rebuilding with a different signing identity may require granting permission again.

### Previews show app icons

Check Screen Recording permission and reopen Flick if macOS requests it. An individual window may still have no available capture; its app icon is the fallback.

### The menu bar icon is missing

On macOS Tahoe, check **System Settings → Menu Bar → Allow in the Menu Bar → Flick**. If it is already enabled, try turning it off and on, then relaunch Flick. If it remains missing, report your macOS version and how you launched the app; Control Center can retain stale app associations.

</details>

## Support Flick

If Flick earns a place in your menu bar, you can [buy me a coffee](https://buymeacoffee.com/boleg) to support its development.
