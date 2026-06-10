# Contributing to GlossPop

Thanks for your interest! GlossPop is AGPL-3.0; by contributing you agree your contributions are licensed under it.

## Ground rules (the project's reason to exist)

- **No resident `CGEventTap` / no global `NSEvent` monitor.** Capture is on-demand only.
- **Never pollute the clipboard.** Accessibility-first; the synthetic-copy fallback is opt-in and must snapshot/restore.
- **Never steal focus.** The result panel is a non-activating `NSPanel`.
- **Degrade gracefully.** Foundation Models is *not* available to everyone (region/eligibility/opt-in) — every path must work without it.
- **Build on documented, stable APIs**; gate new ones with `#available`.

## Dev setup

```bash
brew install xcodegen
make build && make test
```

Edit `project.yml` (not the generated `.xcodeproj`). See the README for the architecture overview.
