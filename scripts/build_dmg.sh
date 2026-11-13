#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/LumoBar.app"
DMG_PATH="$ROOT_DIR/dist/LumoBar.dmg"
DMG_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lumobar-dmg-stage.XXXXXX")"
trap 'rm -rf "$DMG_STAGE"' EXIT

# SKIP_APP_BUILD=1 packages the existing dist/LumoBar.app as is. CI uses it so
# the notarised and stapled app is not rebuilt (and un-stapled) before packaging.
if [[ "${SKIP_APP_BUILD:-0}" == "1" ]]; then
  [[ -d "$APP_DIR" ]] || { echo "error: SKIP_APP_BUILD=1 but $APP_DIR does not exist." >&2; exit 1; }
else
  "$ROOT_DIR/scripts/build_app.sh"
fi

rm -f "$DMG_PATH"
ditto --norsrc --noextattr --noacl "$APP_DIR" "$DMG_STAGE/LumoBar.app"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create \
  -volname "LumoBar" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Sign the DMG itself if a real identity is configured.
SIGN_ID="${SIGNING_IDENTITY:--}"
if [[ "$SIGN_ID" != "-" ]]; then
  codesign --force --sign "$SIGN_ID" "$DMG_PATH"
fi

echo "DMG built: $DMG_PATH"
