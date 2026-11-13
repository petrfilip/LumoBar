# Release process

LampControl ships via GitHub Releases. The release pipeline is fully
automated by the workflow at `.github/workflows/release.yml` and triggered
by pushing a `v*.*.*` tag.

## One-time setup

### 1. Generate the Sparkle EdDSA key pair

You only do this once, then you forget about it.

```bash
# Install Sparkle's tools (homebrew or download from sparkle-project.org/downloads)
brew install --cask sparkle

# Generate keys (puts them in your Keychain by default)
generate_keys

# Print the public key — you'll paste this into GitHub Secrets
generate_keys -p

# Export the private key once for CI
generate_keys -x ~/Desktop/sparkle_private_key
```

> The private key file is plain text. Store it somewhere safe (1Password,
> Bitwarden) and **delete the Desktop copy** as soon as you've added it to
> GitHub Secrets.

### 2. Add GitHub repository secrets

Go to **GitHub → Repo → Settings → Secrets and variables → Actions** and
add:

| Secret | Required | Value |
| --- | --- | --- |
| `SPARKLE_PUBLIC_KEY` | yes | Output of `generate_keys -p` (~44 chars) |
| `SPARKLE_PRIVATE_KEY` | yes | Contents of the file you exported with `generate_keys -x` |
| `SIGNING_IDENTITY` | optional | e.g. `Developer ID Application: Hugo Informatique (TEAMID)` once you have one |
| `APPLE_ID` | optional | Apple ID email used for notarisation |
| `APPLE_APP_PASSWORD` | optional | App-specific password generated at appleid.apple.com |
| `APPLE_TEAM_ID` | optional | 10-char Team ID from developer.apple.com |

The four optional secrets enable real Developer ID signing + notarisation.
Without them, the workflow falls back to ad-hoc signing — releases still
build and Sparkle still verifies the EdDSA signature, but Gatekeeper warns
users on first launch.

### 3. Enable GitHub Pages

- **Repo → Settings → Pages**
- **Source:** *GitHub Actions*

 The workflow uploads the appcast to Pages automatically; this just lets the
 deployment land on `https://hugoinformatique.github.io/LampControl/appcast.xml`,
 which is the URL embedded in `Info.plist` (`SUFeedURL`).

## Cutting a release

1. Update `CHANGELOG.md` with the new version.
2. Bump the marketing version in `Info.plist`
   (`CFBundleShortVersionString`).
3. Commit and push to `main`.
4. Tag and push:
   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```
5. The workflow builds, signs, packages, signs the appcast, creates the
   GitHub Release with the DMG, and updates Pages with the new appcast.
6. Within a minute or two, every running LampControl instance will pick up
   the new appcast on its next scheduled check (or immediately if the user
   clicks **Vérifier maintenant**).

## Manual / ad-hoc release

You can also trigger the workflow manually from **Actions → Release → Run
workflow** and supply a version. Useful for hotfixes when you don't want to
mess with tags.

## Troubleshooting

### Sparkle signature mismatch

Check that `SPARKLE_PUBLIC_KEY` (in `Info.plist` at build time, set by the
workflow) matches the private key in the secret. Regenerating one without
the other instantly breaks all already-installed clients — they will refuse
the next update.

### `notarytool` says invalid credentials

App-specific passwords expire if you change your Apple ID password.
Regenerate at <https://appleid.apple.com/> → Sign-In and Security → App-
Specific Passwords, then update `APPLE_APP_PASSWORD`.

### Pages deployment failed

Check that the *Pages* permission on the workflow run is `write` (it is, by
default in `release.yml`). If a previous deployment is stuck, cancel it from
the Pages settings and re-run.

### Users stuck on an old version

Sparkle checks once every 24 hours by default. Users can force a check from
**Réglages → Mises à jour → Vérifier maintenant**, or via the menu-bar
right-click menu.

## Future work

- **Notarisation** becomes mandatory once the Developer ID is enrolled —
  remove the "ad-hoc fallback" lines in `scripts/build_app.sh` at that
  point.
