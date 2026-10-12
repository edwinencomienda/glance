# Architecture

Glance is a menu bar–only (`LSUIElement`) AppKit app with one SwiftUI view. The
whole design is built around one goal: **⌘⇥ must feel instant.**

## Flow

```
  keyDown ⌘⇥ ──► HotkeyTap (CGEventTap)  ─┐
            └──► GlobalHotkeys (Carbon) ─┴─► SwitcherController.perform (deduped)
                    │
                    ▼
            SwitcherController ─────────────────────────────────────┐
                    │ open()                                         │ step()/commit()/close()
                    ├─► WindowList.current()      one CGWindowList call + Space lookups
                    ├─► WindowMRU.order()         recency across Spaces
                    ├─► SwitcherLayout.make()     pure geometry
                    ├─► model ← cached thumbnails (instant)
                    ├─► ThumbnailService.refresh  async, parallel SCK captures → model
                    └─► Timer(70 ms) ─► SwitcherPanel.show()
                                                                     │
  ⌘ released (flagsChanged, or modifier poll while open) / ↩ / click ─► commit() ─► WindowFocus.focus (background queue)
```

## Components

| File | Responsibility |
| --- | --- |
| `main.swift` | Boots `NSApplication` with `AppDelegate`. |
| `AppDelegate.swift` | Menu bar item, permission prompts and polling, launch at login, signal handlers that restore native ⌘⇥. |
| `GlobalHotkeys.swift` | `RegisterEventHotKey` wrapper. ⌘⇥ / ⌘⇧⇥ are always registered; ⌘+Esc/↩/arrows only while the panel is visible. These still fire under Secure Event Input. |
| `MenuBarIcon.swift` | Draws the logo (`Resources/Logo/glance-logo.svg`) as a template `NSImage` for the status item. Paths mirror the SVG's coordinates. |
| `HotkeyTap.swift` | Session event tap for keyDown/keyUp/flagsChanged. Re-enables itself if macOS disables it on timeout. The handler returns `true` to swallow an event. |
| `SwitcherController.swift` | The state machine (inactive ↔ active) and key bindings. Owns the model, panel and thumbnail service. |
| `WindowList.swift` | Lists layer-0 windows of regular apps on every Space. Returns windows on the visible Spaces (z-order) and on other Spaces separately. Drops windows in no Space (helpers, minimized, inactive tabs), undrawn windows on a visible Space, anything under 100×100, and full-screen overlays (see below). Caches app icons per pid. |
| `Spaces.swift` | Read-only SkyLight lookups: the visible Space per display, which Spaces are full-screen (type 4), and the Spaces a window belongs to. Returns `nil` if the symbols are missing, so listing falls back to the current Space only. |
| `WindowMRU.swift` | Recency stamps per window, updated on app activation and on Glance's own switches. Merges the two lists into one most-recently-used order. |
| `ThumbnailService.swift` | ScreenCaptureKit screenshots at display pixel size, captured in parallel and cached per `CGWindowID`. Each open cancels the previous refresh. |
| `SwitcherModel.swift` | `@Observable` model, plus `SwitcherLayout`: grid sizing, panel size, hit-testing. |
| `SwitcherView.swift` | SwiftUI grid. `TileView` is `Equatable`, so a selection change re-renders only two tiles. |
| `SwitcherPanel.swift` | Borderless, non-activating `NSPanel` with a masked `NSVisualEffectView` (HUD material, 24 pt continuous corners). `MouseCatcher` turns mouse input into hover/click via an always-active tracking area. It's also a drag destination that reports drag hover positions but never accepts a drop. |
| `WindowFocus.swift` | Focuses one exact window: SkyLight `_SLPSSetFrontProcessWithOptions` and the make-key event records, then sets AX main and raises the window, which switches Spaces when needed. Prefetches AX elements for other-Space windows when the switcher opens. Also toggles the native ⌘⇥ symbolic hotkeys. |
| `AXWindowResolver.swift` | Maps a `CGWindowID` to its AX element: tries `kAXWindowsAttribute` first, then falls back to scanning `_AXUIElementCreateWithRemoteToken` element ids, needed for windows on other Spaces. Cached; 200 ms scan budget; 100 ms per-call timeout. |

## Key decisions

- **CGWindowList over Accessibility for listing.** It's two quick IPC calls to the
  WindowServer, and an unresponsive app can't block either. `.optionAll` returns
  windows on other Spaces, including full-screen ones, but in a fixed order that
  is **not** z-order. So a second `.optionOnScreenOnly` call (about 0.6 ms), which
  is front-to-back, ranks the visible-Space windows. Relying on `.optionAll` order
  once froze the switcher's sort order. A per-window
  `CGSCopySpacesForWindows` call (about 24 µs) separates real windows from helper
  windows. Listing takes about 5 ms; building the regular-app table from
  `NSWorkspace.runningApplications`, instead of an `NSRunningApplication` per
  owner, halved it.
- **Full-screen overlays.** A full-screen Space also holds overlay windows that
  aren't switchable. The main one is the toolbar strip that slides down from the
  top edge: full width, about 100 pt tall, untitled, and mostly transparent. It
  showed up as an empty tile that did nothing when chosen. Real windows there
  fill the height, including both halves of Split View, so windows under half the
  tallest window in their full-screen Space are dropped.
- **Switching Spaces = raising the AX element.** Tested on macOS 26 from a
  full-screen Space. Neither `_SLPSSetFrontProcessWithOptions` nor
  `NSRunningApplication.activate()` from a background app switches Spaces. Raising
  the window's AX element does, in both directions. But `kAXWindowsAttribute`
  omits windows on other Spaces (for Ghostty and Edge, at least), so those elements
  are rebuilt from remote tokens: pid + `"coco"` + element id, scanned up to 6000
  (AltTab's technique; Edge's window sat at id ~1500, about 50 ms). To keep a
  switch instant, `open()` prefetches elements for other-Space windows in MRU
  order on the focus queue, and they're cached per window.
- **MRU across Spaces.** The z-order only covers the visible Spaces, so
  `WindowMRU` stamps the front window on every app activation (event-driven, no
  polling) and on each switch. Windows are stable-sorted by stamp. Then the slots
  held by visible-Space windows are refilled in true z-order, which also covers
  focus changes inside one app that never fire an activation. The result: a quick
  ⌘⇥ out of a full-screen video returns to the window you used before it. Logic
  is unit-tested in `WindowMRUTests`.
- **Two input paths.** The event tap gives full keyboard control, but macOS blinds
  it while **Secure Event Input** is on (a focused password field, some terminals).
  Native ⌘⇥ is disabled, so without a second path ⌘⇥ would do nothing there.
  Registered hotkeys are the supported API that keeps working in that case. They
  receive only the exact combos registered, so secure input isn't bypassed. Both
  paths call `perform(_:from:)`, which drops a duplicate of the same action from
  the other source within 50 ms. While the switcher is open, a 60 Hz check of
  `CGEventSource.flagsState` detects ⌘ release, which the tap can't see under
  secure input. It runs only while open, so idle cost stays zero.
- **Drag mode (spring-loading).** If the left mouse button is held when the switcher
  opens, a drag is assumed. Releasing ⌘ no longer commits, and a bare ⇥ keeps
  cycling. A drag hovering a tile selects it. After `springLoadDelay` (0.45 s) the
  tile is *armed*, and it's focused only once ⌘ is released, so the window never
  jumps forward while the shortcut is held. The drag can then continue into it. Mouse-up over a tile
  focuses it; mouse-up anywhere else closes the switcher. Drag hover comes from
  `NSDraggingDestination` callbacks, since mouse-moved events aren't delivered
  during a drag. Drag end is detected by the same open-only input poll that
  watches ⌘.
- **AX is used only for raising,** after the panel has closed, on a background queue
  with a 250 ms messaging timeout.
- **The panel never becomes key.** Keyboard input comes from the event tap, so the
  frontmost app keeps focus until you commit, and dismissing restores nothing.
- **Show delay (70 ms).** A quick tap commits before the panel is ever ordered in.
  You get zero drawing and an instant switch.
- **Cached thumbnails.** The panel opens with the last known frame, and fresh
  captures swap in as they finish (typically a few ms each).
- **Precomputed geometry.** The panel frame is set once (`sizingOptions = []` on the
  hosting view), and hit-testing is arithmetic in `SwitcherLayout.index(at:)`.
- **Private APIs are optional.** They're resolved with `dlsym` at runtime. If one is
  missing, Glance falls back to `NSRunningApplication.activate()` instead of crashing.

## Known limitations

- Minimized windows, hidden apps (⌘H) and inactive native tabs aren't listed.
- Recency within an app on another Space is only as fresh as its last app
  activation (we don't run per-app AX observers, to keep idle cost at zero).
- Only ⌘⇥ is configurable in code (key codes live in `SwitcherController.Key`); there's no settings UI.
- Not notarized.
