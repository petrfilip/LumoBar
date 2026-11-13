# Contributing to LumoBar

Thanks for considering a contribution. LumoBar is a small native macOS
menu-bar app written in Swift / SwiftUI. Anything that improves vendor
coverage, reliability, accessibility, or polish is welcome.

## Quick start

```bash
git clone https://github.com/petrfilip/LumoBar.git
cd LumoBar
swift build
./scripts/build_app.sh
open dist/LumoBar.app
```

You need:

- macOS 13+ on Apple Silicon or Intel.
- Xcode 15.4+ command-line tools (`xcode-select --install`).
- Swift 5.9+ (ships with Xcode 15).

## Project layout

```
Sources/LumoBar/
  AppMain.swift          App entry point
  App/                   AppDelegate, AppState, popover and SwiftUI views
  Models/                Domain models and Tuya DTOs
  Services/              Tuya API client, device service, Sparkle update wrapper
  Store/                 Settings + Keychain persistence
scripts/                 Build / DMG / signing scripts
.github/workflows/       GitHub Actions release pipeline
```

## Adding a new lamp vendor

The Phase 2 roadmap (see `docs/RELEASE.md` and the project README) introduces
a `LampVendor` protocol under `Sources/LumoBar/Vendors/`. To add a new
vendor:

1. Create a folder `Vendors/<VendorName>/`.
2. Implement `LampVendor` (sync, set power, brightness, color).
3. Register it in `VendorRegistry`.
4. Add a settings sub-view exposing the vendor's credentials/discovery flow.
5. Document the credentials/setup in `docs/CONFIGURATION.md`.

Until Phase 2 lands, please open an issue describing the vendor you'd like
to support so we can coordinate.

## Coding guidelines

- Keep all blocking I/O off the main actor; UI types are `@MainActor`.
- Prefer Swift Concurrency (`async`/`await`, `Task`) over Combine for new code.
- Don't store secrets in `SettingsStore` — they belong in `KeychainStore`.
- Don't introduce new dependencies without discussing it in an issue first.

## Pull requests

- Open the PR against `main`.
- Run `swift build` and `swift test`, and confirm `./scripts/build_app.sh` produces a working
  `.app` before requesting review.
- Describe the user-facing change and any setup it requires.
- One vendor / feature per PR — keeps reviews tight.

## Reporting bugs

Open an issue with:

- macOS version and chip (Intel / M-series).
- LumoBar version (Settings → Updates section, or `defaults read cz.tix.lumobar`).
- Steps to reproduce.
- Vendor and lamp model that triggered the bug, if applicable.
- Console logs (`Console.app` → search `cz.tix.lumobar`).

## Licence

By contributing, you agree your contributions are released under the MIT
licence (see `LICENSE`).
