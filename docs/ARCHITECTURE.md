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
                    ├─► WindowList.current()      one CGWindowList call, MRU order
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
| `HotkeyTap.swift` | Session event tap for keyDown/keyUp/flagsChanged. Re-enables itself if macOS disables it on timeout. The handler returns `true` to swallow an event. |
| `SwitcherController.swift` | The state machine (inactive ↔ active) and key bindings. Owns the model, panel and thumbnail service. |
| `WindowList.swift` | Lists layer-0, on-screen windows of regular apps, front to back. Caches app icons per pid. |
| `ThumbnailService.swift` | ScreenCaptureKit screenshots at display pixel size, captured in parallel and cached per `CGWindowID`. Each open cancels the previous refresh. |
| `SwitcherModel.swift` | `@Observable` model, plus `SwitcherLayout`: grid sizing, panel size, hit-testing. |
| `SwitcherView.swift` | SwiftUI grid. `TileView` is `Equatable`, so a selection change re-renders only two tiles. |
| `SwitcherPanel.swift` | Borderless, non-activating `NSPanel` with a masked `NSVisualEffectView` (HUD material, 24 pt continuous corners). `MouseCatcher` turns mouse input into hover/click via an always-active tracking area. It's also a drag destination that reports drag hover positions but never accepts a drop. |
| `WindowFocus.swift` | Focuses one exact window: SkyLight `_SLPSSetFrontProcessWithOptions` and the make-key event records, then AX raise. Also toggles the native ⌘⇥ symbolic hotkeys. |

## Key decisions

- **CGWindowList over Accessibility for listing.** It's one IPC call to the
  WindowServer, already in z-order (= MRU), and an unresponsive app can't block it.
  The trade-off: only on-screen windows in the current Space.
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

- Minimized windows, hidden apps and other Spaces aren't listed.
- Only ⌘⇥ is configurable in code (key codes live in `SwitcherController.Key`); there's no settings UI.
- Not notarized.
