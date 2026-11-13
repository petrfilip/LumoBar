#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/LumoBar.app"
INFO_PLIST_SRC="$ROOT_DIR/Info.plist"
INFO_PLIST_DST="$APP_DIR/Contents/Info.plist"

# Resolve marketing version from VERSION env var, exact git tag, or fall back to Info.plist value.
if [[ -n "${VERSION:-}" ]]; then
  MARKETING_VERSION="${VERSION#v}"
elif git -C "$ROOT_DIR" diff --quiet \
  && git -C "$ROOT_DIR" diff --cached --quiet \
  && git -C "$ROOT_DIR" describe --tags --exact-match --abbrev=0 >/dev/null 2>&1; then
  MARKETING_VERSION="$(git -C "$ROOT_DIR" describe --tags --exact-match --abbrev=0 | sed 's/^v//')"
else
  MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_SRC")"
fi

# Build number = number of commits if not explicitly provided.
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  BUILD_NUMBER_VALUE="$BUILD_NUMBER"
elif git -C "$ROOT_DIR" rev-parse HEAD >/dev/null 2>&1; then
  BUILD_NUMBER_VALUE="$(git -C "$ROOT_DIR" rev-list --count HEAD)"
else
  BUILD_NUMBER_VALUE="1"
fi

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Frameworks"

cp "$BUILD_DIR/LampControl" "$APP_DIR/Contents/MacOS/LampControl"
cp "$INFO_PLIST_SRC" "$INFO_PLIST_DST"

# Bundle app icon
ICON_SRC="$ROOT_DIR/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources"
  cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
else
  echo "Avertissement: Resources/AppIcon.icns introuvable — l'icône sera absente du bundle."
fi

# Bundle localizations (.lproj directories)
LPROJ_SRC="$ROOT_DIR/Sources/LampControl/Resources"
if [[ -d "$LPROJ_SRC" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources"
  for lproj in "$LPROJ_SRC"/*.lproj; do
    if [[ -d "$lproj" ]]; then
      cp -R "$lproj" "$APP_DIR/Contents/Resources/"
    fi
  done
fi

# SwiftPM builds the executable with rpaths pointing into .build/release/
# (so `swift run` works) but the resulting binary can't find embedded
# frameworks like Sparkle when copied into a .app bundle. Strip every
# existing LC_RPATH and add the canonical macOS app-bundle one so
# @rpath/Sparkle.framework/... resolves to Contents/Frameworks/Sparkle...
EXISTING_RPATHS=$(otool -l "$APP_DIR/Contents/MacOS/LampControl" \
  | awk '/LC_RPATH/{rpath=1; next} rpath && /path /{print $2; rpath=0}')
for rp in $EXISTING_RPATHS; do
  install_name_tool -delete_rpath "$rp" "$APP_DIR/Contents/MacOS/LampControl" || true
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/LampControl"

# Inject the resolved versions into the bundled Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$INFO_PLIST_DST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER_VALUE" "$INFO_PLIST_DST"

# Bundle Sparkle.framework if it was built as part of SwiftPM.
SPARKLE_FRAMEWORK_SRC="$BUILD_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK_SRC" ]]; then
  cp -R "$SPARKLE_FRAMEWORK_SRC" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
elif [[ -d "$BUILD_DIR/PackageFrameworks/Sparkle.framework" ]]; then
  cp -R "$BUILD_DIR/PackageFrameworks/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
else
  echo "Avertissement: Sparkle.framework introuvable dans $BUILD_DIR — vérifie que swift build l'a généré."
fi

# Codesign: if SIGNING_IDENTITY is provided (e.g. Developer ID Application: Hugo Informatique),
# perform a hardened-runtime, deep-signed bundle. Otherwise fall back to ad-hoc signing so the
# bundle at least passes Sparkle's own signature checks.
SIGN_ID="${SIGNING_IDENTITY:--}"
ENTITLEMENTS_ARG=()
if [[ -f "$ROOT_DIR/scripts/LampControl.entitlements" ]]; then
  ENTITLEMENTS_ARG=(--entitlements "$ROOT_DIR/scripts/LampControl.entitlements")
fi

# macOS routinely tags files copied from .build/, the Sparkle archive,
# or simply touched by Finder with extended attributes, resource forks,
# AppleDouble ._* files, ACLs, and Finder info. codesign rejects them
# with "resource fork, Finder information, or similar detritus not
# allowed". `xattr -cr` alone misses some of these, so we use `ditto`
# which is the canonical macOS tool to copy a hierarchy while *stripping*
# all metadata. Apply it before codesign steps; nested signing can also
# leave fresh residue that must be stripped before the outer bundle is
# sealed.
strip_metadata() {
  local target="$1"
  local tmp="${target}.cleanup.$$"
  xattr -cr "$target" 2>/dev/null || true
  find "$target" -name '._*' -delete 2>/dev/null || true
  find "$target" -name '.DS_Store' -delete 2>/dev/null || true
  ditto --norsrc --noextattr --noacl "$target" "$tmp"
  rm -rf "$target"
  mv "$tmp" "$target"
}

strip_metadata "$APP_DIR"

# Hardened runtime + secure timestamp only make sense with a real
# Developer ID identity. With ad-hoc signing (SIGN_ID == "-") they cause
# two problems:
#   - --timestamp needs Apple's timestamp server to actually validate,
#     which it can't do for an ad-hoc signature.
#   - On macOS 14+ a framework re-signed ad-hoc with --options runtime
#     fails dyld with "different Team IDs" when loaded into an ad-hoc
#     main bundle. The Sparkle framework ships pre-signed by Sparkle's
#     maintainers, so the moment we re-sign it the Team IDs diverge.
# Drop both flags in the ad-hoc case; keep them when a real identity is
# configured so notarisation can still succeed later.
HARDENED_OPTS=()
if [[ "$SIGN_ID" != "-" ]]; then
  HARDENED_OPTS+=(--options runtime --timestamp)
fi

# Re-sign the Sparkle framework with the same identity as the main bundle
# (this overwrites Sparkle's upstream signature; without this rewrite dyld
# will refuse to load the framework at launch).
if [[ -d "$APP_DIR/Contents/Frameworks/Sparkle.framework" ]]; then
  codesign --force --deep \
    ${HARDENED_OPTS[@]+"${HARDENED_OPTS[@]}"} \
    --sign "$SIGN_ID" \
    "$APP_DIR/Contents/Frameworks/Sparkle.framework"
fi

# Signing Sparkle's nested bundles tends to leave fresh detritus that the
# outer codesign call would reject. Sweep again before the final sign.
strip_metadata "$APP_DIR"

# `${array[@]+"${array[@]}"}` keeps `set -u` happy when the arrays are
# empty.
codesign --force \
  ${HARDENED_OPTS[@]+"${HARDENED_OPTS[@]}"} \
  ${ENTITLEMENTS_ARG[@]+"${ENTITLEMENTS_ARG[@]}"} \
  --sign "$SIGN_ID" "$APP_DIR"

echo "App générée: $APP_DIR (version $MARKETING_VERSION build $BUILD_NUMBER_VALUE, signée: $SIGN_ID)"
