#!/usr/bin/env bash
# Verify that the Sparkle EdDSA public key embedded in the app matches the
# private key used to sign the appcast. A mismatch ships a release that no
# installed copy can ever update to, so CI runs this before building.
#
# Usage:
#   SPARKLE_PUBLIC_KEY=... SPARKLE_PRIVATE_KEY=... \
#     scripts/verify_sparkle_keys.sh <path-to-sign_update>
#
# Keys are read from the environment (never argv) so they stay out of process
# listings. Exits non-zero, with a message, when a key is missing, is still
# the placeholder, is malformed, or when the two keys do not belong together.
#
# How the check works: sign_update signs a throw-away file with the private
# key, then verifies that signature against the *embedded public key*. The
# public key is handed to sign_update through a synthetic 96-byte key file
# (64 unused private bytes + the 32 public bytes), the "older" key format that
# sign_update accepts. Verification only reads the public half.
set -euo pipefail

SIGN_UPDATE="${1:?usage: verify_sparkle_keys.sh <path-to-sign_update>}"

fail() {
  echo "::error::$*" >&2
  exit 1
}

strip_ws() { printf '%s' "$1" | tr -d '\r\n\t '; }

PUBLIC_KEY="$(strip_ws "${SPARKLE_PUBLIC_KEY:-}")"
PRIVATE_KEY="$(strip_ws "${SPARKLE_PRIVATE_KEY:-}")"

[[ -n "$PUBLIC_KEY" ]] || fail "SPARKLE_PUBLIC_KEY is not set. Without it the release could never be updated."
[[ -n "$PRIVATE_KEY" ]] || fail "SPARKLE_PRIVATE_KEY is not set. It is required to sign the appcast."
[[ "$PUBLIC_KEY" != "YOUR_PUBLIC_KEY_HERE" ]] || fail "SPARKLE_PUBLIC_KEY is still the placeholder."
[[ -x "$SIGN_UPDATE" ]] || fail "sign_update not found or not executable: $SIGN_UPDATE"

PUB_BYTES="$(printf '%s' "$PUBLIC_KEY" | openssl base64 -d -A 2>/dev/null | wc -c | tr -d ' ')" || PUB_BYTES=0
[[ "$PUB_BYTES" == "32" ]] || fail "SPARKLE_PUBLIC_KEY must be base64 of 32 bytes (got $PUB_BYTES bytes). Use the output of 'generate_keys -p'."

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sparkle-keycheck.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
umask 077

printf '%s' "$PRIVATE_KEY" > "$WORK_DIR/private_key"
{ head -c 64 /dev/zero; printf '%s' "$PUBLIC_KEY" | openssl base64 -d -A; } \
  | openssl base64 -A > "$WORK_DIR/public_key_only"
printf 'lumobar sparkle key check\n' > "$WORK_DIR/payload"

# stdout only: stderr must never leak into the signature.
SIGNATURE="$("$SIGN_UPDATE" -p -f "$WORK_DIR/private_key" "$WORK_DIR/payload")" \
  || fail "sign_update could not sign with SPARKLE_PRIVATE_KEY (wrong format? expected the file from 'generate_keys -x')."
SIGNATURE="$(strip_ws "$SIGNATURE")"
[[ -n "$SIGNATURE" ]] || fail "sign_update returned an empty signature."

"$SIGN_UPDATE" --verify -f "$WORK_DIR/public_key_only" "$WORK_DIR/payload" "$SIGNATURE" >/dev/null \
  || fail "SPARKLE_PUBLIC_KEY does not match SPARKLE_PRIVATE_KEY. Installed apps would reject every update."

echo "Sparkle key pair verified: the embedded public key matches the signing key."
