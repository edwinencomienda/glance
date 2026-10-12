# Development Guide

## Requirements

- macOS 14+ (developed on macOS 26)
- Xcode 26+ (for the Icon Composer app icon; Swift 5.10+). No Xcode project; it's a plain Swift package.
- Optional: an `Apple Development` signing identity, so permission grants survive rebuilds

## Project layout

```
Package.swift             SwiftPM manifest (app target + test target)
Sources/Glance/           App source (see docs/ARCHITECTURE.md)
Tests/GlanceTests/        Unit tests (pure logic: layout, hit-testing)
Resources/Info.plist      Bundle metadata (LSUIElement, bundle id, usage strings)
Resources/AppIcon.icon/   App icon (Icon Composer bundle, compiled by build-app.sh)
Resources/Logo/           Source artwork (SVG): glance-logo.svg (the mark; the menu
                          bar icon in MenuBarIcon.swift mirrors it, so update both
                          together) and glance-app-icon.svg (flat icon artwork)
scripts/build-app.sh      Builds, bundles and signs Glance.app
docs/                     Developer documentation
```

## Everyday loop

```sh
swift build                     # fast debug compile check
swift test                      # unit tests
scripts/build-app.sh --install  # release build → /Applications → relaunch
```

Use `--install` to try real behaviour. The bundled, signed app is what macOS grants
permissions to. `build-app.sh` quits the running copy before replacing it.

### Running the raw binary

`swift build && .build/debug/Glance` works, but macOS attributes permissions to the
**parent process** (your terminal app), not to Glance. That terminal app
then needs Accessibility and Screen Recording. Prefer the bundled app.

## Icons

- **App icon:** `Resources/AppIcon.icon` is an Icon Composer bundle (`icon.json`
  plus SVG layers in `Assets/`). It has a solid blue fill, a "Windows" layer
  (the tilted cards) and a "Logo" layer. `build-app.sh` compiles it with
  `actool` into `Assets.car`, used by macOS 26+, plus an `AppIcon.icns`
  fallback for macOS 14–15. Building therefore needs Xcode 26 or newer.
  - Edit it in **Icon Composer** (Xcode → Open Developer Tool), or edit the SVGs
    and `icon.json` by hand.
  - Layers are full-bleed: the whole 1024 px canvas is the tile, and the system
    applies the rounded mask, shadows and Liquid Glass effects. The layer SVGs use
    `viewBox="100 100 824 824"` so they keep the coordinates of the flat
    artwork, `Resources/Logo/glance-app-icon.svg`.
  - Don't ship a plain `.icns` on its own. macOS 26 shrinks legacy icons into a
    light-grey "jail" tile, so they look smaller than other apps' icons in Finder
    and Spotlight.
- **Menu bar icon:** drawn in code (`MenuBarIcon.swift`) as a template image from
  the same coordinates as `glance-logo.svg`. If the mark changes, update the
  paths there and `Resources/AppIcon.icon/Assets/logo.svg`.
- Finder and the Dock cache icons. If an old icon sticks after `--install`, run
  `killall Finder` (or `killall Dock`). Your terminal may not be allowed to `touch`
  files in /Applications, because of macOS's App Management protection.

## Permissions

| Permission | Why | Settings pane |
| --- | --- | --- |
| Accessibility | Event tap for ⌘⇥, raising AX windows | Privacy & Security → Accessibility |
| Screen Recording | ScreenCaptureKit thumbnails, window titles | Privacy & Security → Screen & System Audio Recording |

Grants are keyed to the bundle id (`com.edwinencomienda.glance`) plus the code
signature. `build-app.sh` picks the first `Apple Development` identity automatically.
Override it with:

```sh
GLANCE_SIGN_IDENTITY="Apple Development: Name (TEAMID)" scripts/build-app.sh
```

If there's no identity it signs ad-hoc, and you must re-grant after every rebuild.

Reset grants (e.g. to test the first-run flow):

```sh
tccutil reset Accessibility com.edwinencomienda.glance
tccutil reset ScreenCapture com.edwinencomienda.glance
```

After granting Screen Recording, quit and relaunch Glance; macOS applies it on launch.

## Debugging

- **Logs:** `log stream --predicate 'process == "Glance"' --level debug`
  (the app logs with `NSLog`).
- **Native ⌘⇥ stuck off:** Glance turns the system hotkey off while running and
  restores it on quit/SIGTERM/SIGINT/SIGHUP. After a SIGKILL or crash, launch and quit
  Glance again, or log out and back in.
- **⌘⇥ does nothing:** check Accessibility in the menu bar icon. The event tap can't
  be created without it, and the app retries every second until it's granted.
- **⌘⇥ in password fields:** Secure Event Input hides keys from the event tap, so
  ⌘⇥ there comes through `GlobalHotkeys` instead. Check for "failed to register
  hotkey" in the logs. Another app that already owns ⌘⇥ as a registered hotkey
  would block it. `ioreg -l -w 0 | grep SecureInput` shows which process has
  secure input enabled.
- **Thumbnails missing / titles show the app name:** Screen Recording isn't granted, or
  the app wasn't relaunched after granting.
- **Stuck on the current Space after choosing a window:** switching Spaces depends on
  `AXWindowResolver` finding the window's AX element (remote-token scan for other
  Spaces). Check that Accessibility is granted, and that
  `_AXUIElementCreateWithRemoteToken` still resolves.
- **Wrong window focused:** focusing relies on private SkyLight symbols resolved via
  `dlsym` (`WindowFocus.swift`). If a macOS update removes them, it falls back to
  app-level `activate()`. Check `SkyLight.setFrontProcess != nil`.
- **Performance:** profile the bundled app with Instruments (Time Profiler, SwiftUI).
  Idle CPU should be 0%. Open-to-visible should stay well under one frame beyond
  the intentional panel delay (Settings → Switcher, default 70 ms).

## Testing

`swift test` covers the pure logic in `SwitcherLayout` (grid sizing, row balancing,
hit-testing) and `WindowMRU` (ordering across Spaces). Everything that touches the WindowServer, Accessibility or
ScreenCaptureKit needs a manual check. Run this list before merging UI or input
changes:

- [ ] Quick ⌘⇥ tap switches to the previous window with no panel flash
- [ ] Holding ⌘ shows the panel on the screen under the mouse
- [ ] ⇥ / ⇧⇥ / arrow keys move the selection, wrapping at the ends
- [ ] Releasing ⌘, or pressing ↩, focuses the selected window (the right window, not just the app)
- [ ] Esc closes without switching
- [ ] In a focused password field (e.g. a website login, `sudo` in Terminal): ⌘⇥ opens
      the switcher, ⇥ cycles, releasing ⌘ switches, and ⌘ held + Esc cancels
- [ ] Hovering selects (but the panel appearing under a still cursor does not); clicking switches
- [ ] Drag a file from Finder, press ⌘⇥, release ⌘: the panel stays open; hovering the
      drag over a tile focuses that window after ~0.45 s; the drop lands in it
- [ ] In drag mode, hovering a tile while still holding ⌘ only highlights it; it switches
      right after ⌘ is released
- [ ] Dropping a drag on a tile focuses that window; ending the drag outside the panel closes it
- [ ] Thumbnails appear and update; placeholder icons show before the first capture
- [ ] From a full-screen app (e.g. a full-screen video): ⌘⇥ lists windows from the
      desktop and other Spaces, a quick tap returns to the previous window, and
      choosing a window on another Space switches to that Space
- [ ] No blank or tiny helper tiles (e.g. browser toolbar overlays in full screen)
- [ ] The panel follows the Theme setting (System follows macOS), with clean edges: a soft
      shadow that fades out fully (no clipped line), no dark rim, the hairline following
      the corners exactly
- [ ] Many windows (20+) shrink into a grid that fits the screen
- [ ] Works over a full-screen app and on a second display
- [ ] Quitting from the menu bar restores the native ⌘⇥
- [ ] Settings: switching to ⌥⇥ works immediately and gives ⌘⇥ back to macOS;
      switching back to ⌘⇥ takes it over again
- [ ] Settings: hiding the menu bar icon removes it; launching Glance again opens Settings
- [ ] Settings: an excluded app's windows disappear; "Current Space only" hides other Spaces;
      thumbnail size, titles and panel delay apply on the next ⌘⇥
- [ ] With Settings open: Glance appears in the Dock and in ⌘⇥ (Glance's and macOS's), and
      choosing it focuses Settings; closing Settings removes the Dock icon
- [ ] Settings → Show as "App icons": one icon tile per window (titles tell same-app
      windows apart), same ordering and keys, no thumbnails captured

## Conventions

- **Performance first.** Nothing on the ⌘⇥ hot path may do per-app IPC or block the
  main thread. Do slow work (AX, capture) off-main or asynchronously.
- **No polling at idle.** Work happens only in response to events. Short-lived
  checks are fine only while the switcher is open (e.g. the ⌘-release check).
- **New settings** go in `Settings.swift`. Their default must keep the current
  behaviour, and they're read at use time (not observed) unless they truly need
  to apply eagerly. Document them in the README's Settings table.
- **UI on non-Retina displays:** don't rely on thin or fractional strokes (e.g. a
  1.5 pt selection outline). They smear at 1×. Prefer filled shapes, as
  `ChoiceTile` does, and whole-point sizes. Check screenshots on a 1× display.
- **Never bypass Secure Event Input.** Handle it only through supported APIs
  (registered hotkeys, modifier-state reads). Never read or log keystrokes.
- **Private APIs** go through `dlsym` in `WindowFocus.swift` with a public fallback.
  Never link private frameworks directly.
- Keep geometry in `SwitcherLayout` (testable, pure). Views just render it.
- Swift 5 language mode; UI types are `@MainActor`.
- **Docs stay in sync:** any change to behaviour, keys, permissions, build or
  architecture updates `README.md` and the relevant file in `docs/` in the same
  commit.

## Releasing

1. Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist`.
2. `swift test && scripts/build-app.sh`
3. Run the manual checklist above against `build/Glance.app`.
4. Commit and tag `vX.Y.Z`.

Builds are universal (arm64 + x86_64) and signed with the hardened runtime. They
aren't notarized, which is fine for personal use. Distributing to others needs a
Developer ID identity plus `xcrun notarytool`.
