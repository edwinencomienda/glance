# Changelog

All notable changes to Glance are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). See [docs/RELEASING.md](docs/RELEASING.md)
for how releases are made.

## [Unreleased]

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

[Unreleased]: https://github.com/edwinencomienda/glance/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/edwinencomienda/glance/releases/tag/v1.0.0
