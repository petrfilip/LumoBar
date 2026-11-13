# LumoBar landing page

The static page served at https://petrfilip.github.io/LumoBar/. Plain HTML,
CSS and one small script: no build step, no libraries, no external requests.

## Files

- `index.html`: the page (English only).
- `styles.css`: styles, light and dark mode via `prefers-color-scheme`.
- `demo.js`: the interactive demo at the top. An HTML copy of the LumoBar window
  drives the light bar behind the monitor in the photo. The canvas shows
  `room-off.jpg` plus the light the bar adds (`room-lit.jpg` − `room-off.jpg`),
  tinted with the chosen colour and scaled by the brightness. The scene values
  match `LightScenePreset` in the app.
- `room-lit.jpg`, `room-off.jpg`: the same generated photo (ChatGPT image
  generation) with the light bar on (neutral white, full brightness) and off.
  They must line up pixel for pixel; replace them only as a pair.
- `og-image.png`: the social preview image (1200×630), a headless-Chrome
  render of the demo panel alone.
- `icon.png`, `favicon.png`: generated from `Resources/AppIcon.icns`
  (`sips -s format png … --resampleHeightWidth 256 256`).
- `robots.txt`, `sitemap.xml`.

## Rules

- Keep it short and factual: what the app does, how to install it, credits.
- Only describe features that exist, and never show UI the app does not have.
- The demo is a copy of the real window, not a new design: when the popover
  changes in the app, change the demo too.
- The app is free: no prices, no paid tiers.
- Keep the credit to LampControl by Hugo Informatique.

Deployment: `.github/workflows/pages.yml` on changes to `landing/`, and
`release.yml` on every release (together with `appcast.xml`).
