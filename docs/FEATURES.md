# Features

Everything Glance does, grouped by area. The version column says which release
added each feature ("Unreleased" means it's on `main` but not released yet). See
[CHANGELOG.md](../CHANGELOG.md) for fixes and the full history, and the
[README](../README.md) for keys and settings.

## Window switching

| Feature | Since |
| --- | --- |
| **Windows-style switcher on ⌘⇥**: one tile per window (not per app), most recently used first | 1.0.0 |
| **Instant tap**: a quick ⌘⇥ jumps straight to the previous window without drawing anything | 1.0.0 |
| **Keyboard control**: ⇥ / ⇧⇥ to move, arrow keys to navigate, ↩ or releasing ⌘ to switch, Esc to cancel | 1.0.0 |
| **Mouse control**: hover to select, click to switch | 1.0.0 |
| **Windows on every Space**, including full-screen apps; picking one switches to its Space | 1.0.0 |
| **Raises the exact window** you pick, even if it was on another Space or in full screen | 1.0.2 |
| **Works in password fields**: ⌘⇥, ⌘⇧⇥ and ⇥-cycling still work in secure text inputs | 1.0.0 |
| **Same-app switcher**: ⌘` (or ⌥`) shows only the front app's windows as larger tiles; a tap jumps to its previous window | 1.2.0 |
| **Close and quit from the switcher**: hover a tile for a ✕ that closes the window (hold ⌥ to quit the app), or press W / Q; the tile animates away and the switcher stays open | Unreleased |

## Drag-to-switch

| Feature | Since |
| --- | --- |
| **Spring-loading**: while dragging a file, text or image, ⌘⇥ keeps the panel open; hover a window to bring it forward, then drop into it | 1.0.0 |
| **Quick switch while dragging**: a fast ⌘⇥ during a drag jumps to the previous window without the panel, and the drag continues into it | 1.2.0 |

## Window list

| Feature | Since |
| --- | --- |
| **Live thumbnails** captured with ScreenCaptureKit, cached so the panel opens with the last frame | 1.0.0 |
| **App-icon mode** as an alternative to thumbnails | 1.0.0 |
| **Excluded apps**: choose apps whose windows never appear | 1.0.0 |
| **Browser popups hidden**, such as address-bar suggestion dropdowns | 1.0.1 |
| **Short titled windows listed**, such as Finder's "Emptying the Trash…" progress window | 1.0.3 |
| **Settings window listed** in ⌘⇥ while it's open | 1.0.0 |

## Multiple displays

| Feature | Since |
| --- | --- |
| **Panel placement**: show the panel on the pointer's display or the active window's display | 1.2.0 |
| **Per-display filtering**: only list windows on that display | 1.2.0 |

## Appearance

| Feature | Since |
| --- | --- |
| **Theme**: System / Light / Dark, for the switcher and Settings | 1.0.0 |
| **Tile size**: small, medium or large | 1.0.0 |
| **Window titles** on or off | 1.0.0 |
| **Clean panel** with a soft shadow that follows light and dark mode | 1.0.0 |
| **App icon and menu bar logo**, full size on macOS 26 | 1.0.0 |

## Settings and app behaviour

| Feature | Since |
| --- | --- |
| **Branded Settings window**; changes apply immediately | 1.0.0 |
| **Shortcut choice**: ⌘⇥ (replaces the macOS app switcher) or ⌥⇥ (keeps it) | 1.0.0 |
| **Spaces scope**: windows from all Spaces or the current Space only | 1.0.0 |
| **Panel delay** (0–300 ms); a quick tap within it switches without showing the panel | 1.0.0 |
| **Launch at login** | 1.0.0 |
| **Menu bar only**: no Dock icon, with an option to hide the menu bar icon too | 1.0.0 |
| **Permission status** for Accessibility and Screen Recording, with shortcuts to fix them | 1.0.0 |

## Install and updates

| Feature | Since |
| --- | --- |
| **Signed, notarized DMG** on every GitHub release, built by GitHub Actions | 1.1.0 |
| **Update checker**: checks GitHub at most once a day and shows **Glance X.Y.Z Available…** in the menu; never downloads or installs anything itself | 1.1.0 |
| **Check for Updates…** in the menu, plus an Updates section in Settings to turn automatic checks off | 1.1.0 |

## Speed

| Feature | Since |
| --- | --- |
| **Fast window list**: about 5 ms for every window on every Space, with no per-app Accessibility calls on open | 1.0.0 |
| **Non-blocking focus**: runs in the background with a timeout, so a hung app can't freeze the switcher | 1.0.0 |
| **Zero idle cost**: no timers or polling, just an event tap | 1.0.0 |
