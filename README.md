# LumoBar

> One menu-bar app to drive **Philips Hue, LIFX, Tuya / Smart Life, Govee,
> Yeelight, Nanoleaf and WiZ** lamps from macOS. Also runs **Ledvance Smart+
> Wi-Fi** and **Sylvania Smart Wi-Fi** through the Tuya integration (they
> share the Smart Life backend). Native, lightweight, liquid-glass styled,
> Keychain-secure. Free and open source, every feature unlocked.

[![Latest release](https://img.shields.io/github/v/release/petrfilip/LumoBar?label=release)](https://github.com/petrfilip/LumoBar/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/petrfilip/LumoBar/total?label=downloads)](https://github.com/petrfilip/LumoBar/releases)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

LumoBar lives in your macOS menu bar. Click the lightbulb icon to toggle
your lamps, change brightness, pick a colour, or apply a scene to a room
without leaving whatever you're doing.

> **LumoBar is a fork of [LampControl](https://github.com/hugoinformatique/LampControl)
> by Hugo Informatique.** See [Credits](#credits) and
> [What's different from LampControl](#whats-different-from-lampcontrol).

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
Smart Life app, then they appear under the Tuya integration in LumoBar.

Configure as many or as few as you like — lamps from every connected
provider show up in a single list.

---

## Features

- 🪶 **Lightweight menu-bar app** — no dock icon, no Electron, ~5 MB.
- 🌐 **Seven providers in one app** — Hue, LIFX, Tuya, Govee, Yeelight, Nanoleaf, WiZ.
- 💡 **Toggle, dim, recolour and set white temperature** on any compatible bulb, live while you drag.
- 🏠 **Rooms** — group lamps, collapse rooms, drag to reorder.
- 🎨 **Scenes** — built-in and custom scenes, capture the current state of a room and restore it later.
- ⏰ **Automations** — schedule scenes, power on/off and adaptive lighting at set times.
- 🌅 **Adaptive lighting** — colour temperature and brightness follow an editable daily schedule.
- 🎯 **Focus modes** — map a macOS Focus to a scene through Shortcuts automations (`lampcontrol://` URL scheme).
- 🔐 **Keychain-stored secrets** — tokens, API keys and bridge keys never touch plain text files.
- 🌍 **English, French, Spanish and Czech** UI.
- 🚀 **In-app updates via Sparkle**, EdDSA-signed.
- 🆓 **Free and open source** (MIT) — no account, no lamp limit, no paid tier.

## What's different from LampControl

LumoBar started from LampControl 1.3.3. Changes in this fork:

**Removed**
- 🔓 **The Premium tier and licence activation** — rooms, scenes, automations,
  adaptive lighting and Focus modes are available to everyone, for any number
  of lamps.
- ⌨️ **Global keyboard shortcuts.**

**New**
- **Yeelight live state** via push notifications — changes made in other apps
  or on the wall switch show up immediately.
- **Yeelight network discovery** that also follows a bulb when its IP changes.
- **White light** — white swatch and *White* preset, routed to the lamp's
  colour-temperature mode.
- **Editable adaptive lighting schedule**, plus an adaptive toggle in the header.
- **Built-in scenes are regular scenes** — edit or delete them, and restore the
  defaults from Settings.
- **Reset all settings** from Settings.
- **Launch at login** toggle.
- **Menu-bar icon tinted** with the active lamp's colour.
- **Live colour, brightness and temperature** while dragging the sliders.
- **Czech localisation**; error and status messages are localised too.
- **Tooltips** for icon-only controls.
- **Unit test suite.**

**Fixed / improved**
- Yeelight: replies matched by request ID, valid colour decoding, white mode
  kept when changing temperature, commands work right after discovery, back-off
  when a bulb drops the push listener.
- Scenes: capture/room scenes restore power state and survive a failing lamp;
  editing a captured scene keeps its snapshots.
- Adaptive lighting converts percent / Kelvin to each lamp's native scale
  (e.g. Hue mireds).
- Changing brightness or temperature turns an off lamp on; failed previews
  are undone; stale state no longer overrides your value; no slider flicker.
- Automations use a single cancellable timer with reliable de-duplication.
- Focus identifiers match case-insensitively; only mapped Focus modes are
  listed.
- Popover opens on the display whose menu bar was clicked, is sized for that
  display, stays anchored to the icon, and the close button no longer quits
  the app.
- Rooms: collapsed state persists; drag-reorder works for newly added and
  unassigned lamps.
- Settings no longer demand Tuya setup when you use other providers.
- Sparkle does not start without a valid public key; Sparkle bumped to 2.9.5.

## Install

### Option A — Download the DMG

1. Grab the latest DMG from the
   [Releases page](https://github.com/petrfilip/LumoBar/releases/latest).
2. Open `LumoBar-<version>.dmg`, drag `LumoBar.app` to `/Applications`.
   If you had LampControl installed, quit it and delete
   `/Applications/LampControl.app` — LumoBar keeps your existing settings,
   lamps and Keychain secrets.
3. **First launch — bypass Gatekeeper** (the app is ad-hoc signed, not
   notarised; see [known limitations](#known-limitations)).
   On macOS 14+ the right-click → Open trick no longer works on its own:
   1. Double-click `LumoBar.app` once. macOS shows
      *"Apple could not verify «LumoBar»…"*. Click **Done** —
      **not** *Move to Trash*.
   2. Open **System Settings → Privacy & Security**.
   3. Scroll to the **Security** section at the bottom. You'll see:
      *"«LumoBar» was blocked to protect your Mac."* with an
      **Open Anyway** button.
   4. Click **Open Anyway** and authenticate (Touch ID or password).
   5. A new dialog appears with an **Open** button — click it. The app
      starts and macOS remembers your choice.
4. The lightbulb icon appears in your menu bar. Updates delivered through
   Sparkle do not re-trigger this prompt — only the very first install does.

### Option B — Build from source

```bash
git clone https://github.com/petrfilip/LumoBar.git
cd LumoBar
./scripts/build_app.sh
open dist/LumoBar.app
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
     then let LumoBar find it on your network.
4. Lamps appear in the **Lamps** tab as soon as a provider is connected.

The full walkthrough lives in [docs/CONFIGURATION.md](docs/CONFIGURATION.md)
(English) and [docs/CONFIGURATION.fr.md](docs/CONFIGURATION.fr.md) (French).

## Auto-updates

LumoBar uses [Sparkle](https://sparkle-project.org/) for in-app updates.

- Open **Settings → Updates** to check manually or toggle automatic
  checks / installs.
- Updates are signed with an EdDSA key; only releases signed by this fork
  will install.
- Right-click the menu-bar icon to access **Check for Updates…** without
  opening the popover.

## Known limitations

- 🔓 **Ad-hoc signature only.** The app is not notarised, so Gatekeeper
  warns on first launch (see the install steps above).
- 🔁 LumoBar uses the same bundle identifier as LampControl so it can take
  over your existing settings. That also means the two apps can't be
  installed side by side.

## Contributing

Issues and PRs are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md)
first.

## Credits

LumoBar exists thanks to **[Hugo Informatique](https://github.com/hugoinformatique)**,
who created [LampControl](https://github.com/hugoinformatique/LampControl)
and released it under the MIT licence. The multi-provider architecture, the
provider integrations, the liquid-glass UI and most of what you see in this
app are their work. Thank you for building it and for sharing it openly! 🙏

If you'd like to support the original project, check out
[LampControl](https://github.com/hugoinformatique/LampControl).

LumoBar also bundles [Sparkle](https://sparkle-project.org/) (MIT licence).

## Licence

[MIT](LICENSE) — © 2026 Hugo Informatique (original LampControl),
© 2026 Petr Filip (LumoBar fork changes).
