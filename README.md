# Flick

A small window switcher for the Mac. No account.

Hold **Option** and press **Tab**. Release Option on the window you want. Escape stays put. **Option-`** cycles windows in the current app. Arrows, click, and two-finger scroll work while it is open.

## Build

```sh
./build.sh
open Flick.app
```

Quit AltTab first if it is still running. Both listen for Option-Tab.

## Permissions

Accessibility is required for the shortcut and for focusing the window you pick. Screen Recording is only for the previews. Flick still switches without it.

The first time, macOS shows Flick in System Settings. If the shortcut does nothing after you allow it, quit Flick and open it again. Rebuilding with a different signature asks for permission again.

## Verify

```sh
swift test
./build.sh
```

The tests exercise session input ordering and preview cancellation without opening overlays or changing window focus. After changing native input or drawing, check Option-Tab, Option-`, Escape, mouse selection, and scrolling in the running app; multi-display behavior still needs a Mac with multiple displays.
