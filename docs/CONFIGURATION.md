# Configuration guide — Tuya, Hue, LIFX, Govee, Yeelight, Nanoleaf, WiZ

LumoBar talks to seven ecosystems in parallel. You can enable just one or
all of them — the lamp list is merged and sorted by name.

| Brand | Access type | Internet required? |
| --- | --- | --- |
| **Tuya / Smart Life** | Cloud (Access ID + Secret + UID) | Yes |
| **Philips Hue** | Local bridge (LAN) | No (LAN) |
| **LIFX** | Cloud (personal token) | Yes |
| **Govee** | Cloud (Developer API key) | Yes |
| **Yeelight** | Direct LAN (developer mode) | No (LAN) |
| **Nanoleaf** | Local LAN (pairing token) | No (LAN) |
| **WiZ** | Direct LAN (UDP) | No (LAN) |

Each brand has its own settings page in **Settings → Providers**. Jump to the
brand you need:

- [Tuya](#tuya--smart-life)
- [Philips Hue](#philips-hue)
- [LIFX](#lifx)
- [Govee](#govee)
- [Yeelight](#yeelight)
- [Nanoleaf](#nanoleaf)
- [WiZ](#wiz)

---

## Tuya / Smart Life

LumoBar needs four pieces of information to talk to the Tuya Cloud:

1. An **Access ID**
2. An **Access Secret**
3. The **region** of your account (Europe, US West, US East, China, India, …)
4. The **UID** of the Tuya / Smart Life account that owns your lamps

This guide walks you through getting all four. It takes about five minutes
the first time, and you only need to do it once.

> Tuya occasionally renames sections of their portal. If a label below has
> changed, look for the closest equivalent — the underlying flow is stable.

---

## 1. Pair your lamps in the mobile app

Before LumoBar can talk to your lamps, they have to be paired with the
Tuya ecosystem.

- Install **Smart Life** ([iOS](https://apps.apple.com/app/smart-life-smart-living/id1115101477) /
  [Android](https://play.google.com/store/apps/details?id=com.tuya.smartlife))
  or any Tuya-powered app shipped with your lamp.
- Create an account using your **email** (not phone number — it makes the
  cloud linking easier later).
- Pair your lamps following the manufacturer instructions. Confirm you can
  toggle them from the mobile app.

Make a note of:

- The email/phone you used.
- The **country** you selected at sign-up. This is your **region**.

---

## 2. Create a Tuya IoT Cloud project

1. Go to <https://iot.tuya.com/> and **sign in** (or create an account).
2. In the left sidebar, choose **Cloud → Development**.
3. Click **Create Cloud Project**.
4. Fill in:
   - **Project name:** anything (e.g. `LumoBar`).
   - **Industry:** *Smart Home*.
   - **Development Method:** *Custom Development* (or *Smart Home* if Custom
     isn't available).
   - **Data Center:** the one matching your account region:
     - Europe → *Central Europe Data Center*
     - US West → *Western America Data Center*
     - US East → *Eastern America Data Center*
     - China → *China Data Center*
     - India → *India Data Center*
5. Click **Create**.

Tuya prompts you to pick API products. Make sure these are checked:

- **IoT Core**
- **Authorization** (sometimes named *Authorization Token Management*)
- **Smart Home Devices Management**
- **Smart Home Family Management**
- **Smart Home Scene Linkage** (optional, for future scene support)

Click **Authorize**.

---

## 3. Grab your Access ID and Access Secret

1. In your project, open the **Overview** tab.
2. Under **Authorization Key**, copy:
   - **Access ID / Client ID** → this is your **Access ID**.
   - **Access Secret / Client Secret** → this is your **Access Secret**.

> Treat the Access Secret like a password. LumoBar stores it in the macOS
> Keychain, never in plain text.

---

## 4. Link your Smart Life account

This step gives the cloud project access to the lamps you paired with the
mobile app.

1. Open the **Devices** tab of your project.
2. Click **Link Tuya App Account → Add App Account**.
3. Open Smart Life on your phone → **Me** tab → tap the QR scanner icon
   (top-right) → scan the QR code displayed on the Tuya IoT website.
4. Confirm in the app.

The page now lists your linked account, including its **UID**. Copy it.

---

## 5. Pick the matching endpoint

LumoBar auto-fills the endpoint when you choose a region in
**Réglages**. The mapping is:

| Region | Endpoint |
| --- | --- |
| Europe | `https://openapi.tuyaeu.com` |
| US West | `https://openapi.tuyaus.com` |
| US East | `https://openapi-ueaz.tuyaus.com` |
| China | `https://openapi.tuyacn.com` |
| India | `https://openapi.tuyain.com` |

If your data centre isn't listed, choose **Custom** and paste the URL
provided by Tuya in your project's **Overview** tab.

---

## 6. Enter everything in LumoBar

1. Click the lightbulb in your menu bar.
2. Open **Réglages**.
3. Paste:
   - Access ID
   - Access Secret
   - Region (LumoBar auto-fills the endpoint)
   - UID
4. Click **Enregistrer**.

The popover switches to the **Lampes** tab and starts syncing. Within a few
seconds you should see your lamps appear with a power toggle and — for
RGB-capable models — a brightness slider and colour picker.

---

## Troubleshooting

### `Identifiants Tuya incomplets`

One of the four fields is empty. Re-open Réglages and check that:

- Access ID and Access Secret are not swapped.
- The endpoint matches the data centre you picked when creating the project.
- The UID has no leading/trailing whitespace.

### `sign invalid` / HTTP 1004

Almost always means your **system clock is out of sync** (Tuya signatures
include a timestamp). Open **System Settings → General → Date & Time**, make
sure *Set time and date automatically* is on.

### `permission deny` / HTTP 1106

The cloud project doesn't have permission to talk to your lamps. Re-open
your project on the Tuya IoT website, go to **Service API → Authorize** and
ensure all the products listed in step 2 are enabled.

### Lamps appear but won't toggle / change colour

Open the lamp in the Smart Life app and confirm it responds there. If yes,
note the lamp model and open an
[issue](https://github.com/petrfilip/LumoBar/issues) — some firmwares
expose unusual capability codes that we may not yet handle.

### Token expired errors

LumoBar handles token refresh automatically. If you see persistent
expiry errors, click **Enregistrer** again to force-refresh the cached
client.

### `device offline`

The lamp is offline on Tuya's side. Power-cycle the lamp and wait a minute.
LumoBar mirrors the cloud's view; we can't reach a lamp the cloud can't
reach.

---

## FAQ

**Does LumoBar work without internet?**

Partially: Hue and Yeelight run entirely on the local LAN. Tuya, LIFX and
Govee use their respective clouds.

**Where is my Access Secret stored?**

In the macOS Keychain under the service `LampControl.Tuya`, account
`tuya-access-secret`. Other settings live in
`~/Library/Application Support/LampControl/settings.json` in plain JSON.

**Can I use multiple Tuya accounts?**

Not yet — Phase 2's vendor abstraction will support multiple accounts and
multiple vendors side by side.

**Will LumoBar support Bluetooth-only lamps?**

Only lamps that show up in the Tuya Cloud API are reachable. Bluetooth-only
lamps that never sync to the cloud are out of scope.

**Where do I report a bug?**

[GitHub Issues](https://github.com/petrfilip/LumoBar/issues) — please
include macOS version, LumoBar version, and the lamp model.

---

## Philips Hue

LumoBar talks directly to your **Hue bridge** on the local network — no
Hue cloud dependency.

### Step 1 — Find the bridge

1. Plug the Hue bridge into your router (Ethernet) and power it on. The
   middle LED must be solid.
2. Make sure the bridge is on the **same Wi-Fi network** as your Mac.
3. In LumoBar, open **Settings → Providers → Philips Hue → Discover
   bridges**. LumoBar queries `discovery.meethue.com` and lists the
   visible bridges. Pick yours.

> If discovery returns nothing, enter the IP manually (visible in the Hue
> app → Settings → My Hue Devices → Bridge → Network info).

### Step 2 — Pair LumoBar

1. **Physically press the round button** in the centre of the Hue bridge.
2. Within 30 seconds, click **Connect Hue** in LumoBar.
3. An application key is generated and stored in the macOS Keychain under
   the service `LampControl.Hue`.

Your Hue bulbs show up in the **Lamps** tab, with colour and temperature
matching their hardware capabilities.

### Hue troubleshooting

- **"Hue bridge not configured"** — make sure you press the bridge button
  *before* clicking Connect. Try again.
- **No bulbs detected** — open the official Hue app and check your bulbs
  appear there. If not, re-pair them in the Hue app first.
- **Bridge not found on LAN** — power-cycle the bridge, wait for the middle
  LED to be solid, and re-run discovery.

---

## LIFX

LIFX exposes an official cloud API. You need a **personal token**.

### Step 1 — Generate a token

1. Sign in at <https://cloud.lifx.com/sign_in>.
2. Go to **Settings → Personal Access Tokens** (or directly
   <https://cloud.lifx.com/settings>).
3. Click **Generate New Token**, name it (e.g. `LumoBar`).
4. Copy the displayed token — it will never be shown again.

### Step 2 — Enter it in LumoBar

1. **Settings → Providers → LIFX**.
2. Paste the token in **LIFX token**.
3. **Save and sync**.

The token is stored in the macOS Keychain under the service
`LampControl.LIFX`. Bulbs appear in the **Lamps** tab.

### LIFX troubleshooting

- **HTTP 401 / invalid token** — the token was revoked or mistyped.
  Generate a fresh one.
- **No bulbs** — check that your bulbs are properly synced with the official
  LIFX app (so they're visible in the LIFX cloud).
- **HTTP 429 (rate limit)** — the LIFX API caps at ~120 requests/minute per
  token. LumoBar refreshes every minute; if you hammer controls, wait
  30 seconds.

---

## Govee

Govee provides an official HTTP API accessed through an **API key**
requested from their mobile app.

### Step 1 — Request an API key

1. Open the **Govee Home** app on iOS or Android.
2. Go to **My Profile (bottom-right icon) → hamburger menu ☰ → About Us →
   Apply for API Key**.
3. Fill in your name and a reason ("macOS menu bar app" is fine).
4. The key arrives by email within minutes (sometimes hours).

### Step 2 — Enter it in LumoBar

1. **Settings → Providers → Govee**.
2. Paste the **API key** from the email.
3. **Save and sync**.

The key is stored in the macOS Keychain under the service
`LampControl.Govee`.

### Govee troubleshooting

- **HTTP 401 / 403** — the API key is inactive or revoked. Re-apply in the
  Govee Home app.
- **HTTP 429** — Govee caps at **60 requests/minute** per key. Slow down
  actions or wait for the next auto-sync.
- **Bulb missing** — Govee only exposes part of its catalogue through the
  public API. If the Govee Home app drives it but LumoBar doesn't, the
  model isn't in the Govee Developer whitelist (open an issue with the
  model number, but the workaround is on Govee's side).

---

## Yeelight

Yeelight (Xiaomi) exposes a **JSON-RPC LAN protocol** on port 55443. No
cloud, no token — but you must enable **"LAN Control"** on each bulb.

### Step 1 — Enable developer mode on each bulb

1. Open the **Yeelight** app (iOS / Android).
2. Pick your bulb.
3. Tap the settings icon (⚙) in the top-right.
4. Enable **LAN Control** (sometimes called "Developer Mode" or "Local
   network control").
5. Note the **IP address** shown in **Device info**.

> Repeat for every bulb. If LAN Control isn't visible, update the bulb's
> firmware from the app first.

### Step 2 — Add it in LumoBar

1. **Settings → Providers → Yeelight**.
2. Click **Search network**. LumoBar lists every bulb with LAN Control
   enabled on your network; click **+** next to each one you want.
3. If a bulb isn't found (some routers block multicast), enter its **IP**
   instead (e.g. `192.168.1.42`, optionally `:port`), an optional **name**,
   and click **Add and sync**.

LumoBar subscribes to each bulb's push notifications, so changes made in the
Yeelight app or with a wall switch show up immediately.

The list is stored in plain JSON at
`~/Library/Application Support/LampControl/yeelight-settings.json` (no
secret to protect — there's no key or password).

### Yeelight troubleshooting

- **"Timed out"** — LAN Control is disabled, or Mac and bulb are on
  different networks (watch out for guest VLANs). Test with:

  ```bash
  nc -vz 192.168.1.42 55443
  ```

- **Bulb offline** — power-cycle the bulb, wait 30 seconds, click **Sync
  now**.
- **IP changed** — Yeelight bulbs use DHCP. LumoBar's network discovery
  recognises a known bulb by its ID and updates the stored IP. If that does
  not happen (multicast blocked), remove the entry and re-add it with the
  new IP. Better: reserve an IP in your router.

---

## Nanoleaf

Nanoleaf panels (Shapes, Canvas, Elements, Lines, Light Panels) expose a
local **OpenAPI** on port 16021. Pairing creates a token that LumoBar keeps
in the macOS Keychain.

### Step 1 — Find the panel's IP

Open the Nanoleaf app, pick the panel and look at the device info, or find
the controller in your router's list of connected devices.

### Step 2 — Pair it in LumoBar

1. **Settings → Providers → Nanoleaf**.
2. Enter the **IP** (e.g. `192.168.1.50`) and an optional **name**.
3. On the controller, **hold the power button for 5–7 seconds** until the
   LEDs start flashing. The controller now accepts pairing for about
   30 seconds.
4. Click **Pair and sync** within that window.

### Nanoleaf troubleshooting

- **Pairing fails / HTTP 403** — the pairing window closed. Hold the power
  button again and click **Pair and sync** straight away.
- **Timed out** — the Mac and the panel are on different networks, or the
  port is blocked. Test with `nc -vz 192.168.1.50 16021`.
- **IP changed** — remove the panel and pair it again with the new IP, or
  reserve an IP in your router.

---

## WiZ

WiZ bulbs (Signify, also sold under the Philips "WiZ" label) talk a local
**UDP** protocol on port 38899. No account and no token.

### Step 1 — Find the bulb's IP

In the **WiZ** app, open the bulb's settings → **Device info**. Make sure
**Allow local communication** is enabled in the app's privacy/settings
section (newer firmware turns it off by default).

### Step 2 — Add it in LumoBar

1. **Settings → Providers → WiZ**.
2. Enter the **IP** (e.g. `192.168.1.55`) and an optional **name**.
3. Click **Add and sync**. Repeat for each bulb.

### WiZ troubleshooting

- **Timed out** — local communication is disabled in the WiZ app, or the Mac
  and the bulb are on different networks (guest Wi-Fi, VLAN).
- **IP changed** — WiZ bulbs use DHCP. Remove the entry and re-add it, or
  reserve an IP in your router.
