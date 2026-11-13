# Changelog

All notable changes to LumoBar are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - Unreleased

First release of **LumoBar**, a fork of
[LampControl](https://github.com/hugoinformatique/LampControl) 1.3.3 by
Hugo Informatique. LumoBar keeps LampControl's bundle identifier, settings
folder and Keychain entries, so an existing LampControl install carries over:
quit LampControl, delete it and install LumoBar.

### Changed

- **Renamed to LumoBar.** Updates come from the fork's own Sparkle feed
  (`petrfilip.github.io/LumoBar/appcast.xml`).
- **Everything is free.** The Premium tier and licence activation are gone:
  rooms, scenes, automations, adaptive lighting and Focus modes work for any
  number of lamps.
- Background polling pauses while the Mac sleeps or the screen is locked and
  refreshes right after wake.
- Built-in scenes are regular scenes (edit, delete, restore defaults).
- Network requests have explicit timeouts (5 s on the LAN, 15 s for clouds).

### Removed

- Global keyboard shortcuts.
- The home-screen widget snapshot and other dead code.
- The French README and configuration guide (docs are English-only; the app
  stays localised in English, French, Spanish and Czech).

### Added

- Yeelight live state via push notifications, network discovery that follows
  a bulb whose IP changed, and a back-off when a bulb drops the listener.
- White light: a white swatch and *White* preset using colour-temperature mode.
- Editable adaptive-lighting schedule and an adaptive toggle in the header.
- Reset all settings, launch at login, a menu-bar icon tinted with the active
  lamp's colour, and live colour/brightness/temperature while dragging.
- Czech localisation, VoiceOver labels and tooltips for icon-only controls.
- A dismiss button on status banners; errors expire after 15 s, data-recovery
  notices stay until dismissed.
- A unit test suite (370+ tests).

### Fixed

- **Data safety:** a settings file that cannot be read is moved aside as
  `<name>.corrupt-<date>.json` and reported, instead of being overwritten;
  files are decoded leniently so one bad entry no longer loses the rest.
- **Secrets:** the Nanoleaf token moved from JSON to the Keychain.
- **Concurrency:** the busy state is re-entrant, stale polls can no longer
  overwrite newer state, and background tasks are owned and cancelled.
- Yeelight replies are matched by request ID; colours decode correctly; white
  mode is kept when changing temperature.
- Scenes restore power state, survive a failing lamp and keep snapshots when
  edited; deleting a scene closes its editor and clears references to it.
- Adaptive lighting converts percent/Kelvin to each lamp's native scale.
- Changing brightness or temperature turns an off lamp on; failed previews are
  undone; no slider flicker.
- The popover opens on the clicked display, sized for it, and the close button
  no longer quits the app.
- Room drag-reorder resets correctly when a drag is cancelled.
- Settings no longer demand Tuya setup when other providers are used.
- Release workflow: actions pinned by SHA, the release no longer wipes the
  landing site, and a missing Sparkle key fails the build instead of shipping
  an app that can never update.

---

## LampControl history

The entries below are from the original LampControl project.

## [1.3.3] - 2026-05-14

### Fixed

- **Sparkle auto-update was broken since 1.3.0.** `SUFeedURL` pointed at the
  GitHub `releases/latest` REST endpoint, which returns JSON. Sparkle expects
  an XML appcast, so every "Check for updates" returned
  *"Erreur pendant la mise à jour"*. Repointed the feed at
  `https://hugoinformatique.github.io/LampControl/appcast.xml` (the appcast
  the release workflow already publishes to GitHub Pages on every tag).
  Also fixed the typo in the previous URL host (`hugo-informatique` →
  `hugoinformatique`).
- **"Vérifier automatiquement" / "Installer automatiquement" toggles did
  nothing and reset on every launch.** `UpdateService` held them as plain
  `@Published` Bools that were never read from nor written to Sparkle.
  Toggling them now updates `SPUUpdater.automaticallyChecksForUpdates`
  and `automaticallyDownloadsUpdates` (Sparkle persists them in
  `UserDefaults` under their canonical keys), and the seed values are
  loaded from Sparkle on init so the UI matches reality at launch.
- **App did not check for updates on launch even with auto-checks
  enabled.** `UpdateService.start()` was a no-op. It now triggers
  `checkForUpdatesInBackground()` once at launch when auto-checks are
  enabled — previously users could wait up to 24h for the next scheduled
  Sparkle poll.

> **Manual install required this time:** users currently on 1.3.0/1.3.1/
> 1.3.2 cannot auto-update to 1.3.3 because their installed bundle still
> carries the broken JSON `SUFeedURL`. Download the 1.3.3 DMG manually
> from the Releases page once; auto-update will work for every release
> after that.

## [1.3.2] - 2026-05-14

### Changed

- **Quiet Glass UI redesign.** Introduce a dedicated `DesignSystem.swift`
  (tokens for spacing, radius, typography, animation, palette) and rebuild
  the popover with an opinionated, premium "quiet glass" direction:
  - Native `.glassEffect(.regular)` on macOS 26+ (with `.tint` and
    `.interactive` variants), layered material fallback on macOS 13–25
    (`.regularMaterial` + window-coloured base + thin gradient border).
  - Sticky chrome (header + optional message banner) with an opaque
    background so scrolling content cannot bleed through.
  - Tab strip removed entirely. The header gear icon now toggles
    Lamps ↔ Settings, and the title swaps so the user always knows
    which surface they are on.
  - Stripped per-section card wrappers (status bar, room groups,
    unassigned section). Premium apps use layout/typography for hierarchy,
    not stacked glass cards.
  - Room headers replace the cluttered "All on / All off / palette" chip
    bar with one overflow `…` menu — fixes the long-room-name wrap
    (e.g. "CHAMBRE" wrapping to two lines in French).
  - Setup-summary card in Settings is lighter: a single check icon +
    label + thin progress capsules (one per setup step) instead of the
    heavy 4/4 ring on a green-tinted card.

### Performance

- **Popover reaches 60 FPS again.** Three big offenders fixed:
  1. Removed `.lcHoverable` from `LampRow`, `SettingsView` provider /
     link rows, and from inside `LCGlassButtonStyle`. The modifier holds
     `@State isHovering` and re-renders every row on every mouse move.
  2. Simplified `LCBackdrop` to a single `.regularMaterial` + soft accent
     halo (previous `.drawingGroup()` cache was making text shimmer on
     macOS 14/15).
  3. Shortened `LCAnimation` tokens (standard 0.45 → 0.28, micro 0.25 →
     0.18) — long springs feel laggy in a small popover.

### Fixed

- Popover bottom no longer clipped on the Lamps tab. Recomputed the
  popover height with real Quiet Glass metrics; the inner ScrollView
  now absorbs overflow with `.frame(maxHeight: .infinity).layoutPriority(1)`
  so the chrome cannot compress the content.
- Search-bar clear button (`xmark.circle.fill`) hit-target restored
  via explicit `.frame(22, 22) + .contentShape(Circle())`.
- Header / Settings overlap on dark mode (regular material was too
  translucent against the popover backdrop) — chrome now layers a
  `Color(nsColor: .windowBackgroundColor)` fill under the material and
  uses `.zIndex(1)` + `.clipped()` to fence the scroll area.

## [1.3.1] - 2026-05-13

### Fixed

- **Global keyboard shortcuts now work when the app is in background.**
  Replaced `NSEvent.addGlobalMonitorForEvents` (which silently required the
  Accessibility permission and never fired without it) with the Carbon
  `RegisterEventHotKey` API. Shortcuts like ⌥1, ⌥2, ⌥0 now trigger their
  scene/power actions instantly from any application, no permission prompt
  required.
- **Click targets across the popover.** Numerous icon-only buttons (tab
  switcher, room expand/collapse, "All On"/"All Off", scene palette, color
  swatches, edit/trash icons in Settings, search-bar clear) had hit-areas
  limited to the inner glyph. Added `.contentShape(...)` with expanded
  frames so the entire visible surface is now clickable.

### Changed

- **Liquid Glass design pass.** `ControlCenterView` now applies the native
  `.glassEffect(.regular)` API on macOS 26+ (with `tint` and `interactive`
  variants) and a richer layered fallback on macOS 13–25 combining
  `.ultraThinMaterial`, gradient tint layer, top highlight overlay, and
  luminous gradient stroke border.
- `GlobalShortcutService` is now `@MainActor`-isolated to prevent any
  future thread-safety issues.

### Removed

- `NSAccessibilityUsageDescription` from `Info.plist` — no longer needed
  since shortcuts use Carbon (which does not require Accessibility).

## [1.1.0] - 2026-05-02

### Added

- **Full internationalization (i18n)** — LampControl is now available in English,
  French, and Spanish. The app automatically detects the macOS system language and
  switches accordingly. Falls back to English if the system language is unsupported.
- `Sources/LampControl/Resources/en.lproj/Localizable.strings` — 120+ English
  translation keys.
- `Sources/LampControl/Resources/fr.lproj/Localizable.strings` — French translations
  (app native language, full coverage).
- `Sources/LampControl/Resources/es.lproj/Localizable.strings` — Spanish translations.
- `Sources/LampControl/L10n.swift` — helper namespace for dynamic/format strings
  (`L10n.syncTime(_:)`, `L10n.hiddenLamps(_:)`, day-of-week arrays, etc.).
- `Info.plist`: `CFBundleLocalizations` declares `en`, `fr`, `es`.
- `Package.swift`: `defaultLocalization: "en"` and `resources: [.process("Resources")]`.
- `scripts/build_app.sh`: automatically copies `.lproj` directories into the app
  bundle's `Contents/Resources/` at packaging time.

### Changed

- All user-visible strings in `LampsView`, `ControlCenterView`, `OnboardingOverlay`,
  `SettingsView`, and `PremiumSettingsView` replaced with localization keys.
- `AutomationAction.title`, `Automation.weekdaysLabel`, `ShortcutAction.title`,
  `LicenseTier.title`, `LicenseState.statusText`, and `LightScenePreset.presets`
  now return localized strings via `L10n`.
- Context menu items in `AppDelegate` (`Open`, `Check for Updates`, `About`, `Quit`)
  are now localized.
- Scene preset title "Nuit" is now "Night" (EN) / "Noche" (ES) in their respective
  locales.

## [1.0.15] - 2026-05-02

### Changed

- **Profils fusionnés dans les Scènes** — `UserLightScene` gère désormais deux
  modes : "Couleur" (comportement existant, applique une couleur aux lampes RGB)
  et "Capturer" (snapshot complet de l'état de toutes les lampes : power,
  brightness, température, couleur). Un toggle dans l'éditeur de scène permet
  de choisir le mode à la création. Les scènes de type capture affichent un
  badge visuel distinctif sur le chip.
- `LampProfile`, `ProfileStore`, `ProfileBar`, `SaveProfileButton` supprimés.
- `LicenseEntitlements.canUseProfiles` supprimé (les captures sont couvertes
  par `canUseCustomScenes`).
- `AppState` : +`captureCurrentState()`, +`applyCapture(snapshots:name:)` ;
  `saveUserScene` accepte désormais un paramètre `snapshots`.

### Fixed

- Apple notarization and Developer ID signature.
- HomeKit / Matter bridge.
- WidgetKit macOS widget (requires Xcode project restructure).
- Siri / AppIntents integration.
- Full English UI localization.

## [1.0.13] - 2026-05-02

### Added

- **Profils** — snapshot de l'état complet de toutes les lampes (power,
  brightness, température, couleur). Créer via le bouton + dans la ProfileBar,
  appliquer en un clic, supprimer via menu contextuel. Affiché dans LampsView
  au-dessus des scènes. Gated Premium.
- **Éclairage adaptatif (Circadian)** — ajuste automatiquement la luminosité et
  la température de couleur selon l'heure. 6 keyframes par défaut (06h→22h).
  Interpolation linéaire entre les points. Mise à jour toutes les 15 min.
  Toggle rapide dans LampsView, configuration complète dans Réglages. Gated Premium.
- **Automations** — planifications horaires récurrentes (heure fixe, jours
  filtrables). Actions disponibles : éteindre tout, allumer tout, appliquer une
  scène ou un profil, activer/désactiver l'éclairage adaptatif. Scheduler Timer
  aligné à la minute. Création via formulaire inline. Gated Premium.
- `LicenseEntitlements` : +`canUseProfiles`, +`canUseAutomations`,
  +`canUseAdaptiveLighting` (tous activés en earlyAccess et premium).

## [1.0.12] - 2026-05-02

### Added

- **Nanoleaf provider** — panels paired over LAN (REST, port 16021). Pairing
  flow: hold power button 5-7s, then tap "Appairer" in settings. Supports
  power, brightness (0-100), color temperature (1200-6500K), and hue/sat color.
- **WiZ provider** (Signify) — bulbs controlled over LAN via UDP port 38899.
  Manual IP entry, no authentication required. Full power, brightness
  (1-100), color temperature (2200-6500K), and RGB color support (HSV↔RGB
  conversion included).
- **Global keyboard shortcuts** — configurable hotkeys without opening the
  popover. Defaults: ⌥0 Éteindre tout · ⌥1 Focus · ⌥2 Relax · ⌥3 Neon ·
  ⌥4 Nuit. Toggle on/off per shortcut in Réglages → Raccourcis clavier.
  Uses `NSEvent.addGlobalMonitorForEvents` — no Accessibility permission
  required.

### Changed

- `LightProviderKind` extended with `.nanoleaf` and `.wiz`.
- Settings overview now shows Raccourcis clavier link.
- Provider list includes Nanoleaf and WiZ with dedicated configuration pages.

## [1.0.11] - 2026-05-02

### Changed

- **LampsView**: Lamp icon changed to lightbulb (more semantic), SceneChips
  taller (52px) with shadow, MetricPill values larger and monospaced, RGB group
  button now shows an icon, status dot larger with glow effect, brightness
  slider tinted amber, temperature label shows Chaud/Froid instead of %, color
  swatch border subtler, sync button uses circle variant.
- **ControlCenterView**: Error messages now shown with red icon and tinted
  surface (vs. blue for info). Status dot pulses when auto-syncing. Active tab
  has bottom capsule indicator. Added semantic color tokens to LCTheme
  (error, errorSurface, infoSurface, success).
- **SettingsView**: Configured providers highlighted in green. Provider rows
  have hover glass surface. All save buttons height standardized to 38px.
  API key fields have autocorrection disabled. Hint text blocks now show info
  icon. Fixed old GitHub username in configuration guide URL.
- **OnboardingOverlay**: Background scrim tappable to dismiss. Escape key
  dismisses. Step circles use accent tint instead of filled circles. Card
  width flexible (maxWidth 380).

### Fixed

- `openConfigurationGuide()` URL was pointing to old GitHub username
  (`huggooo26`) — fixed to `hugoinformatique` in both AppState and SettingsView.

## [1.0.10] - 2026-05-02

### Fixed

- Tuya: "Lampe inconnue" error after sync — the internal device cache was
  keyed by the full prefixed ID (`tuya:XXXXX`) but control actions passed the
  native ID. Cache is now keyed by `nativeID`, matching what AppState sends.
- Sparkle update feed URL corrected from the old GitHub username
  (`huggooo26.github.io`) to `hugoinformatique.github.io`; update checks now
  resolve correctly.
- App icon now displayed in Finder/Applications folder; `AppIcon.icns` is
  embedded in the bundle via `build_app.sh` and referenced in `Info.plist`.

## [1.0.9] - 2026-05-02

### Fixed

- Tuya: commands (power, brightness, temperature, color) were sent to the wrong
  API endpoint because the full prefixed device ID (`tuya:XXXXX`) was used
  instead of the native device ID. Sync worked correctly; only control actions
  were affected.

## [1.0.8] - 2026-04-28

### Added

- LIFX Cloud provider with personal-token authentication, lamp sync, and full
  power/brightness/temperature/color controls.
- Govee Cloud provider with API key authentication, device state retrieval,
  and full controls (HSV → RGB conversion handled client-side).
- Yeelight LAN provider over JSON-RPC port 55443 using `Network.framework`,
  with manual IP entry, per-bulb persistence, and graceful offline detection.
- Dedicated provider settings pages for Govee and Yeelight (add/remove bulbs,
  Keychain-stored API keys).
- Bilingual configuration guide updated with end-to-end setup instructions
  and troubleshooting for all five providers.

### Changed

- The provider overview now treats every brand as implemented; the "Bientôt"
  placeholder is gone.
- README and CONFIGURATION docs restructured around the five-provider matrix.

## [1.0.7] - 2026-04-26

### Added

- Started the multi-provider architecture with a generic light provider layer,
  a Tuya provider adapter, and a provider settings overview ready for Philips
  Hue, LIFX, Yeelight, and Govee.
- Added the first Philips Hue integration with bridge discovery, local pairing,
  secure keychain storage, lamp sync, and light controls.
- Quick RGB scene presets can now apply Focus, Relax, Neon, or Night ambiance
  to the selected lamps, or to every online RGB lamp when nothing is selected.
- Custom RGB scenes can now be created, edited, deleted, persisted locally,
  and applied with the same selected-or-all RGB targeting behavior.
- Added the first Premium/Early Access licensing foundation with local
  entitlements, a Premium settings panel, and feature gates ready for server
  validation.
- Added the Lemon Squeezy activation flow with license activation, validation,
  deactivation, and configurable product checks.

## [1.0.6] - 2026-04-25

### Added

- Settings now use an Apple Settings-inspired menu/submenu layout with
  dedicated Tuya, devices, updates, and about panels.
- First-run onboarding now guides new users through the Tuya setup flow with
  direct actions for Settings and the configuration guide.

### Changed

- The app now follows the Mac's current light or dark appearance instead of
  forcing the light theme.
- Static glass surfaces now use a calmer fallback rendering to avoid visible
  wave/refraction artifacts in dense dark-mode lists.
- Popover rendering now favors lightweight surfaces and disables resize/open
  animations so sliders and buttons remain responsive.

### Fixed

- RGB color changes preserve the current color brightness value instead of
  unexpectedly dimming compatible LED strips.
- Tuya `colour_data` scaling now follows the device specification when
  available, avoiding 0...255 scaling on LED strips that expect 0...1000 HSV.

## [1.0.5] - 2026-04-25

### Added

- Guided Tuya setup checklist in Settings with completion state and a direct
  configuration guide shortcut.
- "Save and test" Settings action that stores credentials and immediately
  runs a lamp sync.
- Warm/cool white temperature controls for Tuya lamps that expose
  `temp_value` or `temp_value_v2`.

### Fixed

- Tuya ON/OFF commands now use the switch code reported by each device
  instead of assuming every lamp supports `switch_led`.
- Warm/cool white updates no longer force `work_mode = white`, which some
  white-only E27 bulbs reject with Tuya error 2008.
- RGB+CCT bulbs now use their dedicated `bright_value` capability for
  brightness instead of incorrectly changing the HSV color value.
- Legacy Tuya `colour_data` colors are now scaled to the older 0...255
  saturation/value range instead of the v2 0...1000 range.
- Color and white-temperature updates retry without `work_mode` when a device
  rejects the batched mode switch.
- Tuya command failures now include the command codes that were attempted,
  making device-specific compatibility bugs easier to diagnose.
- Popover resizing is now debounced and the global size animation removed so
  sliders feel more responsive.
- Liquid Glass fallbacks are lighter, less shadow-heavy, and button surfaces
  stay visible on macOS versions without native glass button styles.

## [1.0.4] - 2026-04-25

### Fixed

- Release builds now set `CFBundleVersion` to the same value advertised in
  the appcast so Sparkle does not keep offering the same update.

## [1.0.3] - 2026-04-25

### Fixed

- Release packaging now strips extended attributes before signing Sparkle
  bundles and stages the DMG from a clean temporary directory, avoiding
  codesign failures caused by Finder metadata on nested Sparkle helpers.

## [1.0.2] - 2026-04-25

### Fixed

- Bundle `LampControl.app` now embeds the correct `LC_RPATH` entry
  (`@executable_path/../Frameworks`) so dyld can locate the bundled
  `Sparkle.framework` at launch. Previous builds aborted with
  `Library not loaded: @rpath/Sparkle.framework/...` because SwiftPM
  rpaths point into the build directory and aren't relocatable.

## [1.0.1] - 2026-04-25

### Fixed

- Appcast `<enclosure>` no longer carries a duplicated `length=` attribute.
  The release workflow now uses `sign_update -p` to grab only the EdDSA
  signature and assembles the enclosure tag manually, so Sparkle clients
  receive a clean appcast item.

## [1.0.0] - 2026-04-25

### Added

- Native macOS menu-bar app for Tuya / Smart Life lamps.
- Tuya Cloud API integration (sign-in, device sync, capability detection).
- Power toggle, brightness slider, RGB colour picker, group scene control.
- Auto-sync every 60 seconds when credentials are configured.
- Liquid-glass styled UI compatible with macOS 13+ and enhanced on macOS 26+.
- Keychain storage for the Tuya Access Secret; non-secret settings persisted
  to `~/Library/Application Support/LampControl/settings.json`.
- Sparkle 2 auto-update integration with EdDSA-signed appcast.
- "Check for Updates…" command in the status-bar menu and a dedicated
  "Mises à jour" section in the in-app settings.
- GitHub Actions release workflow that builds, signs, packages a DMG,
  signs the appcast, publishes a GitHub Release, and deploys the appcast
  to GitHub Pages on every `v*.*.*` tag.
- Bilingual documentation (English `README.md`, French `README.fr.md`,
  configuration guides under `docs/`).
- MIT licence and contributing guide.

[Unreleased]: https://github.com/hugoinformatique/LampControl/compare/v1.0.6...HEAD
[1.0.6]: https://github.com/hugoinformatique/LampControl/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/hugoinformatique/LampControl/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/hugoinformatique/LampControl/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/hugoinformatique/LampControl/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/hugoinformatique/LampControl/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/hugoinformatique/LampControl/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/hugoinformatique/LampControl/releases/tag/v1.0.0
