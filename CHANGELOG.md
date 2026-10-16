# Changelog

All notable changes to Glance are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). See [docs/RELEASING.md](docs/RELEASING.md)
for how releases are made.

## [Unreleased]

### Added

- Same-app window switcher: turn it on in Settings → Shortcut, then ⌘` (or ⌥`
  with the ⌥⇥ shortcut) works like ⌘⇥ but shows only the front app's windows.
  A quick tap jumps to that app's previous window. With ⌘⇥ it replaces macOS's
  own ⌘` window cycling.
- Multiple displays: Settings → Switcher can show the panel on the active
  window's display instead of the pointer's, and can list only the windows on
  that display.

## [1.1.0] - 2026-10-15

### Added

- Releases now include a signed and notarized `Glance.dmg`, so you can install
  Glance without building it yourself.
- Glance tells you when a new version is out. It checks GitHub at most once a
  day, shows **Glance X.Y.Z Available…** in the menu bar menu, and has
  **Check for Updates…** in the menu and an Updates section in Settings. It
  never downloads or installs anything by itself, and you can turn automatic
  checks off.

## [1.0.3] - 2026-10-13

### Fixed

- Short windows with a title, such as Finder's "Emptying the Trash…" progress
  window, now show up in the switcher.

## [1.0.2] - 2026-10-13

### Fixed

- Switching to a window could activate its app without bringing the window to the
  front, if the window had been on another Space or in full screen earlier.

## [1.0.1] - 2026-10-12

### Fixed

- Browser popups, such as Microsoft Edge's address-bar suggestions, no longer show
  up as windows in the switcher.

## [1.0.0] - 2026-10-12

The first release.

### Added

- Windows-style window switcher on ⌘⇥: one tile per window, most recently used
  first. A quick tap jumps straight to the previous window without drawing anything.
- Live window thumbnails (ScreenCaptureKit), or app icons only.
- Windows from every Space, including full-screen apps. Choosing a window on
  another Space switches to it.
- Keyboard (⇥ / ⇧⇥, arrows, ↩, Esc) and mouse (hover, click) control.
- Drag-to-switch: while dragging a file, text or image, ⌘⇥ keeps the panel open.
  Hover a window to bring it forward and drop into it.
- Works in secure text fields (password inputs) via registered hotkeys.
- Settings window: launch at login, menu bar icon, ⌘⇥ or ⌥⇥ shortcut,
  Spaces scope, panel delay, theme (System / Light / Dark), thumbnails or icons,
  size, window titles, excluded apps, permission status.
- Menu bar icon and app icon (Icon Composer, full-size on macOS 26).
- Clean panel that follows light and dark mode, with a soft shadow.

[Unreleased]: https://github.com/edwinencomienda/glance/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/edwinencomienda/glance/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/edwinencomienda/glance/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/edwinencomienda/glance/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/edwinencomienda/glance/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/edwinencomienda/glance/releases/tag/v1.0.0
