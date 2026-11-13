# LumoBar landing page

Static landing page for LumoBar, a free and open source (MIT) macOS menu-bar
app for smart lights. LumoBar is a fork of LampControl by Hugo Informatique.
The page is plain HTML, CSS and one small JS file, with no build step and no
external dependencies.

Live site: https://petrfilip.github.io/LumoBar/

## Files

- `index.html`: English page (site root).
- `fr/index.html`: French page.
- `es/index.html`: Spanish page.
- `cs/index.html`: Czech page.
- `styles.css`: shared design system (dark terminal / amber look).
- `script.js`: header scroll state and the "copy install command" button. Its
  button messages are localised by the page's `lang` attribute.
- `og-image.svg`: Open Graph / Twitter image, shared by every language.
- `robots.txt` and `sitemap.xml`: SEO files for the canonical site.

All language pages share the same structure: hero with a Terminal install
command, highlights strip, problem and solution, "what is different" table
(changes compared with LampControl), install steps (including the first-launch
"Open Anyway" step), FAQ, final call to action, and a footer crediting
LampControl by Hugo Informatique.

## Conventions

- English is the root page. The other languages live in `fr/`, `es/` and `cs/`
  and reference the shared assets with `../styles.css` and `../script.js`.
- Every page carries the canonical link, `hreflang` alternates (with
  `x-default` pointing to the English root), Open Graph / Twitter tags, and
  JSON-LD (`SoftwareApplication` and `FAQPage`).
- The language switcher is repeated in each page's header. When adding a
  language, update the switcher and `hreflang` links in every page and add the
  URL to `sitemap.xml`.
- Keep the visible FAQ and the `FAQPage` JSON-LD in sync.
- The product is free, so the page must not mention prices, licences to buy or
  locked features. Keep the credit to the original project in each footer.

## Deployment

The folder can be served as is by GitHub Pages or any static host. It is not
referenced by `Package.swift`, the Swift build scripts or the macOS DMG.
The canonical URLs assume `https://petrfilip.github.io/LumoBar/`; change them
in every page, `robots.txt` and `sitemap.xml` if the site moves.

## Local preview

    python3 -m http.server --directory landing 8000

Then open http://localhost:8000/ (and `/fr/`, `/es/`, `/cs/`).
