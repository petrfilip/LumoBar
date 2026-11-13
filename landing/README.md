# LumoBar landing page

The static page served at https://petrfilip.github.io/LumoBar/. It is plain
HTML and CSS: no JavaScript, no build step, no external requests.

## Files

- `index.html`: the page (English only).
- `styles.css`: styles, light and dark mode via `prefers-color-scheme`.
- `screenshot.png`: a real screenshot of the app. Retake it when the UI
  changes; never replace it with a mock-up.
- `og-image.png`: the social preview image (1200×630).
- `icon.png`, `favicon.png`: generated from `Resources/AppIcon.icns`
  (`sips -s format png … --resampleHeightWidth 256 256`).
- `robots.txt`, `sitemap.xml`.

## Rules

- Keep it short and factual: what the app does, how to install it, credits.
- Only describe features that exist, and only show real screenshots.
- The app is free: no prices, no paid tiers.
- Keep the credit to LampControl by Hugo Informatique.

Deployment: `.github/workflows/pages.yml` on changes to `landing/`, and
`release.yml` on every release (together with `appcast.xml`).
