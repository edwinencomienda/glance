# Glance

A tiny, fast, Windows-style window switcher for macOS. Press **⌘⇥** to see every
window, with live thumbnails, not just every app.

## Usage

| Keys | Action |
| --- | --- |
| `⌘⇥` (tap) | Jump to the previous window instantly; no UI appears |
| `⌘⇥` (hold ⌘) | Show the switcher; each `⇥` moves forward |
| `⌘⇧⇥` | Move backward |
| `←` `→` `↑` `↓` | Navigate while the switcher is open |
| Release `⌘` / `↩` | Switch to the selected window |
| `esc` | Cancel |
| Mouse | Hover to select, click to switch |
| Drag + `⌘⇥` | While dragging a file, text or image: the panel stays open; release `⌘`, then hover the drag over a window for a moment (or drop on it) to bring that window forward, then drop into it. Nothing switches while `⌘` is still held |

Glance lives in the menu bar (no Dock icon). The menu shows permission status,
**Launch at Login** and **Quit**.

## Build & install

```sh
scripts/build-app.sh            # builds build/Glance.app
scripts/build-app.sh --install  # builds, copies to /Applications, launches
```

Requires macOS 14+ and Xcode / Swift 5.10+.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the dev loop, debugging, testing
and releasing, and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it works.
Run the tests with `swift test`.

## Permissions

- **Accessibility**: needed to intercept ⌘⇥ and raise the chosen window.
- **Screen Recording**: needed for thumbnails and window titles.

Grants are tied to the code signature. The build script signs with your first
`Apple Development` identity, so grants survive rebuilds. If there isn't one, it
falls back to ad-hoc signing, and you'll need to re-grant after each rebuild. Set
`GLANCE_SIGN_IDENTITY` to choose an identity.

## How it stays fast

- **Window list**: one `CGWindowListCopyWindowInfo` call, already in
  most-recently-used order. No per-app Accessibility IPC on open.
- **Delayed panel**: the panel appears after 70 ms, so a quick tap never draws.
- **Thumbnails**: captured in parallel with ScreenCaptureKit, at the exact pixel
  size shown. Cached per window, so the panel opens with the last frame and
  updates in place.
- **Geometry**: computed once up front. The panel is sized in one step, and
  mouse hit-testing is plain arithmetic.
- **Focusing**: runs on a background queue with a 250 ms AX timeout, so a hung
  app can't freeze the switcher.
- **Idle cost**: zero. No timers or polling, just an event tap.

## Notes & limitations

- In secure text fields (e.g. password inputs), macOS hides keystrokes from apps.
  ⌘⇥, ⌘⇧⇥ and ⇥-cycling still work, and so do ⌘+Esc / ⌘+↩ / ⌘+arrows while ⌘ is
  held. Glance never reads what you type.
- Shows on-screen windows in the current Space. Minimized windows, hidden apps
  and other Spaces aren't listed.
- Uses private SkyLight APIs, as AltTab does, to disable the native ⌘⇥ and to
  focus a specific window. They're loaded at runtime, so if they're missing it
  falls back to public APIs instead of crashing. Native ⌘⇥ is restored on quit,
  including on SIGTERM/SIGINT. After a hard crash (SIGKILL), relaunch Glance and
  quit it, or log out, to get native ⌘⇥ back.
