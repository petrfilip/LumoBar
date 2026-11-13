#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# SwiftPM scratch directory. Override with SCRATCH_PATH to build elsewhere
# (defaults to the usual .build).
SCRATCH_PATH="${SCRATCH_PATH:-$ROOT_DIR/.build}"
BUILD_DIR="$SCRATCH_PATH/release"
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

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version '$MARKETING_VERSION' is not MAJOR.MINOR.PATCH (e.g. 1.2.3)." >&2
  exit 1
fi

# Build number = number of commits on HEAD (CFBundleVersion, and the appcast's
# sparkle:version in CI). The count is identical locally and in CI as long as
# the clone is complete, so shallow clones are rejected: their count would be
# wrong and could make Sparkle think a newer build is older. BUILD_NUMBER can
# still be passed explicitly.
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  BUILD_NUMBER_VALUE="$BUILD_NUMBER"
elif git -C "$ROOT_DIR" rev-parse HEAD >/dev/null 2>&1; then
  if [[ "$(git -C "$ROOT_DIR" rev-parse --is-shallow-repository)" == "true" ]]; then
    echo "error: shallow clone: the commit count is unreliable. Use 'fetch-depth: 0' (CI) or 'git fetch --unshallow', or set BUILD_NUMBER." >&2
    exit 1
  fi
  BUILD_NUMBER_VALUE="$(git -C "$ROOT_DIR" rev-list --count HEAD)"
else
  BUILD_NUMBER_VALUE="1"
fi
if [[ ! "$BUILD_NUMBER_VALUE" =~ ^[0-9]+$ ]]; then
  echo "error: build number '$BUILD_NUMBER_VALUE' is not an integer." >&2
  exit 1
fi

cd "$ROOT_DIR"
swift build -c release --scratch-path "$SCRATCH_PATH"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Frameworks"

cp "$BUILD_DIR/LumoBar" "$APP_DIR/Contents/MacOS/LumoBar"
cp "$INFO_PLIST_SRC" "$INFO_PLIST_DST"

# Bundle app icon
ICON_SRC="$ROOT_DIR/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources"
  cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
else
  echo "warning: Resources/AppIcon.icns not found; the icon will be missing from the bundle."
fi

# Bundle localizations (.lproj directories)
LPROJ_SRC="$ROOT_DIR/Sources/LumoBar/Resources"
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
EXISTING_RPATHS=$(otool -l "$APP_DIR/Contents/MacOS/LumoBar" \
  | awk '/LC_RPATH/{rpath=1; next} rpath && /path /{print $2; rpath=0}')
for rp in $EXISTING_RPATHS; do
  install_name_tool -delete_rpath "$rp" "$APP_DIR/Contents/MacOS/LumoBar" || true
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/LumoBar"

# Inject the resolved versions into the bundled Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$INFO_PLIST_DST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER_VALUE" "$INFO_PLIST_DST"

# Sparkle EdDSA public key. Info.plist already carries LumoBar's key; setting
# SPARKLE_PUBLIC_KEY overrides it in the bundled copy only (CI passes the
# secret, which verify_sparkle_keys.sh checks against the signing key).
if [[ -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  CLEAN_PUBLIC_KEY="$(printf '%s' "$SPARKLE_PUBLIC_KEY" | tr -d '\r\n\t ')"
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $CLEAN_PUBLIC_KEY" "$INFO_PLIST_DST"
  echo "Embedded SUPublicEDKey (${#CLEAN_PUBLIC_KEY} chars)"
fi

# Bundle Sparkle.framework if it was built as part of SwiftPM.
SPARKLE_FRAMEWORK_SRC="$BUILD_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK_SRC" ]]; then
  cp -R "$SPARKLE_FRAMEWORK_SRC" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
elif [[ -d "$BUILD_DIR/PackageFrameworks/Sparkle.framework" ]]; then
  cp -R "$BUILD_DIR/PackageFrameworks/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
else
  echo "warning: Sparkle.framework not found in $BUILD_DIR; check that swift build produced it."
fi

# Codesign: if SIGNING_IDENTITY is provided (e.g. Developer ID Application: Hugo Informatique),
# perform a hardened-runtime, deep-signed bundle. Otherwise fall back to ad-hoc signing so the
# bundle at least passes Sparkle's own signature checks.
SIGN_ID="${SIGNING_IDENTITY:--}"
ENTITLEMENTS_ARG=()
if [[ -f "$ROOT_DIR/scripts/LumoBar.entitlements" ]]; then
  ENTITLEMENTS_ARG=(--entitlements "$ROOT_DIR/scripts/LumoBar.entitlements")
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

echo "App built: $APP_DIR (version $MARKETING_VERSION build $BUILD_NUMBER_VALUE, signed with: $SIGN_ID)"
