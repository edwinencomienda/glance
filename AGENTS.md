# AGENTS.md

Guidance for AI agents and contributors working in this repo.

## What this is

Glance: a native macOS (14+) Windows-style window switcher bound to ⌘⇥. It's a Swift
package with no Xcode project. Read `docs/ARCHITECTURE.md` before changing behaviour.

## Commands

- `swift build`: compile check
- `swift test`: unit tests (must pass before committing)
- `scripts/build-app.sh [--install]`: bundled, signed app (needed to test real behaviour)

## Rules

- **Speed is the product.** Don't add per-app IPC, synchronous AX calls or blocking
  work to the ⌘⇥ path. Don't add timers or polling at idle.
- Private APIs only via `dlsym` in `WindowFocus.swift`, always with a public fallback.
- Keep geometry pure and tested in `SwitcherLayout`. Add tests for any logic that
  can run without the WindowServer.
- After UI or input changes, run the manual checklist in `docs/DEVELOPMENT.md`.
- **Keep docs in sync in the same change:**
  - user-facing behaviour, keys, permissions → `README.md`
  - build, debug, test or release workflow → `docs/DEVELOPMENT.md`
  - components, data flow or design decisions → `docs/ARCHITECTURE.md`
- Never commit build output (`.build/`, `build/`) or signing material.
