# Release process

LumoBar ships via GitHub Releases and a Sparkle appcast on GitHub Pages. The
release pipeline is automated by `.github/workflows/release.yml` and triggered
by pushing a `v<MAJOR>.<MINOR>.<PATCH>` tag. A second workflow,
`.github/workflows/pages.yml`, redeploys the landing page without a release.

## How the pipeline fits together

| Workflow / job | Runs on | Permissions | What it does |
| --- | --- | --- | --- |
| `release.yml` / `build` | macOS | `contents: read` | Validates the version, verifies the Sparkle key pair, builds, signs, (optionally) notarises, packages the DMG, signs it with the Sparkle key, assembles the Pages site (`landing/` + `appcast.xml`). |
| `release.yml` / `release` | Ubuntu | `contents: write` | Creates the GitHub Release (tag `vX.Y.Z`) and uploads the DMG with `gh`. |
| `release.yml` / `deploy-pages` | Ubuntu | `pages: write`, `id-token: write` | Deploys the Pages site. Runs after `release`, so the appcast never points to a DMG that is not published yet. |
| `pages.yml` / `deploy` | Ubuntu | `contents: read`, `pages: write`, `id-token: write` | On a push to `main` that touches `landing/**` (or manually), deploys `landing/` and re-ships the **current live** `appcast.xml`. |

The Pages site hosts both the landing page and the appcast
(`https://petrfilip.github.io/LumoBar/appcast.xml`, the `SUFeedURL` in
`Info.plist`). Every deployment replaces the whole site, which is why both
workflows ship both. If no appcast is live yet (HTTP 404), `pages.yml`
deploys without it and does not fail; any other download error fails the
run so the appcast is never dropped by accident.

Both deploy jobs share the concurrency group `pages` (no cancellation), so a
release and a landing deploy never run at the same time. The group is set on
the deploy jobs, not on whole workflows, so a queued landing deploy can never
cancel a release build. In the rare case where a landing deploy replaces a
*queued* release deploy, re-run the release's `deploy-pages` job.

### Versions and build numbers

- **Marketing version** (`CFBundleShortVersionString`, `sparkle:shortVersionString`)
  comes from the tag (or the manual input). It must match
  `^[0-9]+\.[0-9]+\.[0-9]+$`; anything else fails the run. There is no default.
- **Build number** (`CFBundleVersion`) is the number of commits on `HEAD`
  (`git rev-list --count HEAD`). CI checks out the full history
  (`fetch-depth: 0`) so it equals what `scripts/build_app.sh` computes on a
  developer machine. `build_app.sh` refuses to run in a shallow clone.
- **`sparkle:version`** in the appcast is read from the built app's
  `CFBundleVersion`, so the two can never differ. Sparkle compares this number
  to decide whether an update is newer, so it must only ever grow: do not
  rewrite history on `main`.

### Sparkle tools and supply chain

- `sign_update` is taken from the SwiftPM-resolved Sparkle package
  (`.build/artifacts/sparkle/Sparkle/bin/sign_update`). SwiftPM
  checksum-verifies that binary and it is always the same Sparkle version as
  the framework bundled into the app (see `Package.resolved`). Nothing is
  downloaded with `curl`.
- All actions are pinned by full commit SHA, with the tag in a comment. To
  update one, look up the new tag's commit and replace both the SHA and the
  comment. The GitHub Release is created with the `gh` CLI that ships on the
  runner, so there is no third-party release action.
- Values from `inputs`, step outputs and secrets are passed through `env:`
  and quoted in the scripts, never interpolated into `run:` text.
- The signature is captured from `sign_update`'s stdout only.

## One-time setup

### 1. Generate the Sparkle EdDSA key pair

You only do this once, then you forget about it.

```bash
# Use Sparkle's tools. After `swift build` they are available at
# .build/artifacts/sparkle/Sparkle/bin/ (or: brew install --cask sparkle).
TOOLS=.build/artifacts/sparkle/Sparkle/bin

# Generate keys (puts them in your Keychain by default)
$TOOLS/generate_keys

# Print the public key (you'll paste this into GitHub Secrets)
$TOOLS/generate_keys -p

# Export the private key once for CI
$TOOLS/generate_keys -x ~/Desktop/sparkle_private_key
```

> The private key file is plain text. Store it somewhere safe (1Password,
> Bitwarden) and **delete the Desktop copy** as soon as you've added it to
> GitHub Secrets.

### 2. Add GitHub repository secrets

Go to **GitHub → Repo → Settings → Secrets and variables → Actions** and
add:

| Secret | Required | Value |
| --- | --- | --- |
| `SPARKLE_PUBLIC_KEY` | **yes** | Output of `generate_keys -p` (44 chars, base64 of 32 bytes) |
| `SPARKLE_PRIVATE_KEY` | **yes** | Contents of the file you exported with `generate_keys -x` |
| `SIGNING_IDENTITY` | optional | e.g. `Developer ID Application: Your Name (TEAMID)`. See "Code signing" below. |
| `APPLE_ID` | optional | Apple ID email used for notarisation |
| `APPLE_APP_PASSWORD` | optional | App-specific password generated at appleid.apple.com |
| `APPLE_TEAM_ID` | optional | 10-char Team ID from developer.apple.com |

The two Sparkle secrets are **mandatory**. The release fails, before building
anything, if either one is missing, if the public key is still the
`YOUR_PUBLIC_KEY_HERE` placeholder, or if the public key does not match the
private key. The check (`scripts/verify_sparkle_keys.sh`) signs a throw-away
file with the private key and verifies it against the public key that will be
embedded. This guards against shipping a release that no installed copy could
ever update to.

The public key is embedded into the *bundled* `Info.plist` by
`scripts/build_app.sh` (from the `SPARKLE_PUBLIC_KEY` environment variable);
the `Info.plist` in the repository keeps the placeholder.

The four optional secrets enable real Developer ID signing + notarisation.
Without them, the workflow falls back to ad-hoc signing: releases still build
and Sparkle still verifies the EdDSA signature, but Gatekeeper warns users on
first launch.

### 3. Enable GitHub Pages

- **Repo → Settings → Pages**
- **Source:** *GitHub Actions*
- **Repo → Settings → Environments → `github-pages` → Deployment branches
  and tags:** besides `main`, allow the tag pattern `v*`. By default only the
  default branch may deploy to this environment, so a deploy triggered by a
  tag push is rejected until you add the tag rule.

The first deployment lands on `https://petrfilip.github.io/LumoBar/`, and
`appcast.xml` next to it is the URL embedded in `Info.plist` (`SUFeedURL`).
You can run **Actions → Pages → Run workflow** once to publish the landing
page before the first release.

## Cutting a release

1. Update `CHANGELOG.md` with the new version.
2. Bump the marketing version in `Info.plist`
   (`CFBundleShortVersionString`). The build overrides it from the tag; this
   just keeps local builds consistent.
3. Commit and push to `main`.
4. Tag and push:
   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```
5. The workflow builds, signs, packages, signs the appcast, creates the
   GitHub Release with the DMG, and deploys the landing page together with the
   new appcast to Pages.
6. Within a minute or two, every running LumoBar instance will pick up the
   new appcast on its next scheduled check (or immediately if the user clicks
   **Check now** in Settings → Updates).

## Manual / ad-hoc release

You can also trigger the workflow manually from **Actions → Release → Run
workflow** and supply a version (`MAJOR.MINOR.PATCH`, required). Useful for
hotfixes when you don't want to mess with tags. If the tag `vX.Y.Z` does not
exist, the Release job creates it on the commit the workflow ran for. If the
Release already exists (a re-run), its DMG is replaced.

## Local build

```bash
./scripts/build_app.sh      # dist/LumoBar.app
./scripts/build_dmg.sh      # dist/LumoBar.dmg
```

Useful environment variables: `VERSION` (marketing version, default: exact
git tag or `Info.plist`), `BUILD_NUMBER` (default: commit count),
`SIGNING_IDENTITY` (default: ad-hoc), `SPARKLE_PUBLIC_KEY`, `SCRATCH_PATH`
(SwiftPM build directory, default `.build`), `SKIP_APP_BUILD=1`
(`build_dmg.sh` only: package the existing `dist/LumoBar.app`).

## Code signing and the Keychain prompt

With **ad-hoc signing** (the default without `SIGNING_IDENTITY`) every build
has a different code identity. macOS ties Keychain access to that identity,
so after **every update** the app is asked again for permission to read its
own Keychain items (the stored cloud-account credentials), and users see a
Keychain prompt each time.

A **stable code-signing identity** avoids this, because the identity stays the
same from one release to the next:

- a Developer ID certificate (paid Apple Developer account), which also
  enables notarisation; or
- a **self-signed code-signing certificate** (Keychain Access → Certificate
  Assistant → Create a Certificate → type *Code Signing*). It is free and keeps
  the Keychain prompts away, but Gatekeeper still warns on first launch
  because it is not notarised.

Note: `release.yml` currently only passes `SIGNING_IDENTITY` to the build; it
does **not** import a certificate into the runner's keychain. Before using
either option, add a step that imports the certificate (for example a base64
`.p12` secret loaded into a temporary keychain with `security import` and
unlocked for `codesign`) ahead of "Build, bundle and sign app".

## Troubleshooting

### The release fails at "Verify Sparkle EdDSA keys"

Read the error: it says which secret is missing or unusable, or that the
public and private keys do not match. Re-export the pair from the same
Keychain item (`generate_keys -p` and `generate_keys -x`) and update both
secrets. Regenerating one without the other instantly breaks all
already-installed clients, which will refuse the next update.

### `notarytool` says invalid credentials

App-specific passwords expire if you change your Apple ID password.
Regenerate at <https://appleid.apple.com/> → Sign-In and Security →
App-Specific Passwords, then update `APPLE_APP_PASSWORD`.

### Pages deployment failed

- "Tag `vX.Y.Z` is not allowed to deploy to github-pages": add the `v*` tag
  rule to the `github-pages` environment (see setup step 3).
- Check that Pages is set to the *GitHub Actions* source.
- If a previous deployment is stuck, cancel it from the Actions tab and
  re-run the `deploy-pages` job.

### The landing page was deployed but the appcast is gone

Run **Actions → Release → Re-run jobs** for the latest release (or push a new
tag): every release ships the appcast again. `pages.yml` never removes a live
appcast, but it cannot recreate one that was never published.

### Users stuck on an old version

Sparkle checks once every 24 hours by default. Users can force a check from
**Settings → Updates → Check now**, or via the menu-bar right-click menu.

## Future work

- **Notarisation** becomes mandatory once the Developer ID is enrolled: remove
  the "ad-hoc fallback" lines in `scripts/build_app.sh` at that point, and
  add the certificate import step described above.
- The appcast holds only the latest release. Keep older items if you ever need
  to support skipping versions or delta updates.
