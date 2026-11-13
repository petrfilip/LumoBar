# LampControl

> One menu-bar app to drive **Philips Hue, LIFX, Tuya / Smart Life, Govee,
> Yeelight, Nanoleaf and WiZ** lamps from macOS. Also runs **Ledvance Smart+
> Wi-Fi** and **Sylvania Smart Wi-Fi** through the Tuya integration (they
> share the Smart Life backend). Native, lightweight, liquid-glass styled,
> Keychain-secure.
>
> 🇫🇷 [Lire ce README en français](README.fr.md)

[![Latest release](https://img.shields.io/github/v/release/hugoinformatique/LampControl?label=release)](https://github.com/hugoinformatique/LampControl/releases/latest)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

LampControl lives in your macOS menu bar. Click the lightbulb icon to toggle
your lamps, change brightness, pick a colour, or apply a group scene without
leaving whatever you're doing.

It speaks to **seven ecosystems in parallel**:

| Brand | Access | Internet? |
| --- | --- | --- |
| Philips Hue | Local bridge (LAN) | No |
| LIFX | Cloud (personal token) | Yes |
| Tuya / Smart Life | Cloud (Access ID + Secret + UID) | Yes |
| Govee | Cloud (Developer API key) | Yes |
| Yeelight | Direct LAN (developer mode) | No |
| Nanoleaf | Local LAN (auth token) | No |
| WiZ | Direct LAN (UDP) | No |

**Compatible OEMs (no extra setup):** Ledvance Smart+ Wi-Fi and Sylvania
Smart Wi-Fi bulbs use the Tuya / Smart Life backend — pair them in the
Smart Life app, then they appear under the Tuya integration in LampControl.

Configure as many or as few as you like — lamps from every connected
provider show up in a single sorted list.

---

## Features

- 🪶 **Lightweight menu-bar app** — no dock icon, no Electron, ~5 MB.
- 🌐 **Seven providers in one app** — Hue, LIFX, Tuya, Govee, Yeelight, Nanoleaf, WiZ (also covers Ledvance & Sylvania Smart Wi-Fi via Tuya).
- 💡 **Toggle, dim and recolour** any compatible bulb.
- 🎨 **Group scenes** — select multiple RGB lamps and apply one colour.
- 🔁 **Auto-sync** every 60 seconds, silently in the background.
- 🔐 **Keychain-stored secrets** — tokens, API keys and bridge keys never touch plain text files.
- 🚀 **Auto-update via Sparkle** — push to `main`, users get notified next launch.
- 🆓 Open source under the MIT licence.

## Install

### Option A — Download the DMG

1. Grab the latest DMG from the
  [Releases page](https://github.com/hugoinformatique/LampControl/releases/latest).
2. Open `LampControl.dmg`, drag `LampControl.app` to `/Applications`.
3. **First launch — bypass Gatekeeper** (the app is ad-hoc signed until we
   enrol an Apple Developer ID; see [known limitations](#known-limitations)).
   On macOS 14+ the right-click → Open trick no longer works on its own:
   1. Double-click `LampControl.app` once. macOS shows
      *"Apple could not verify «LampControl»…"*. Click **Done** —
      **not** *Move to Trash*.
   2. Open **System Settings → Privacy & Security**.
   3. Scroll to the **Security** section at the bottom. You'll see:
      *"«LampControl» was blocked to protect your Mac."* with an
      **Open Anyway** button.
   4. Click **Open Anyway** and authenticate (Touch ID or password).
   5. A new dialog appears with an **Open** button — click it. The app
      starts and macOS remembers your choice.
4. The lightbulb icon appears in your menu bar. Updates delivered through
   Sparkle do not re-trigger this prompt — only the very first install does.

### Option B — Build from source

```bash
git clone https://github.com/hugoinformatique/LampControl.git
cd LampControl
./scripts/build_app.sh
open dist/LampControl.app
```

Requires macOS 13+, Xcode 15.4+ command-line tools, and Swift 5.9+.

## Quick start

1. Click the lightbulb in your menu bar.
2. Open **Settings → Providers**.
3. Pick the brands you own and follow the dedicated section in the
   [configuration guide](docs/CONFIGURATION.md):
   - **Tuya** — Access ID + Secret + UID + region (~5 min).
   - **Philips Hue** — auto-discover the bridge, press its physical button,
     click *Connect*.
   - **LIFX** — generate a personal token at
     [cloud.lifx.com/settings](https://cloud.lifx.com/settings) and paste it.
   - **Govee** — request an API key from the Govee Home app (*About → Apply
     for API Key*).
   - **Yeelight** — enable *LAN Control* on each bulb in the Yeelight app,
     then add its IP.
4. Lamps appear in the **Lamps** tab as soon as a provider is connected.

The full bilingual walkthrough lives in
[docs/CONFIGURATION.md](docs/CONFIGURATION.md) (English) and
[docs/CONFIGURATION.fr.md](docs/CONFIGURATION.fr.md) (French).

## Auto-updates

LampControl uses [Sparkle](https://sparkle-project.org/) for in-app updates.

- Open **Réglages → Mises à jour** to check manually or toggle automatic
  checks / installs.
- Updates are signed with an EdDSA key; only releases signed by the project's
  maintainers will install.
- Right-click the menu-bar icon to access **Check for Updates…** without
  opening the popover.

## Roadmap

- **Phase 1:** Tuya support, auto-update, bilingual docs, public release. ✅
- **Phase 2:** Vendor abstraction + Philips Hue, LIFX, Govee, Yeelight. ✅
- **Phase 4:** Notarisation, automatic install on launch, onboarding tour.
- **Phase 5:** Localisation (English UI), HomeKit bridge, automation triggers.

## Known limitations

- 🔓 **Ad-hoc signature only.** Until a paid Apple Developer ID is enrolled,
  Gatekeeper will warn on first launch. Right-click → *Open* once and macOS
  remembers your choice.
- 🇫🇷 The in-app UI labels are currently in French; full localisation is on
  the way.

## Contributing

PRs welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening one.

## Licence

[MIT](LICENSE) © 2026 Hugo Informatique.

LampControl bundles [Sparkle](https://sparkle-project.org/), distributed under
the MIT licence.
