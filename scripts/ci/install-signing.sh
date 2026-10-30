#!/usr/bin/env bash
# Import the fixed Apple Distribution certificate and App Store provisioning
# profile into the CI keychain. Creates nothing on Apple's side.
#
# Environment: KEYCHAIN, KEYCHAIN_PASSWORD (from the Create keychain step),
#   DIST_CERT_P12_BASE64, DIST_CERT_PASSWORD, PROVISIONING_PROFILE_BASE64
set -euo pipefail

missing=()
for v in DIST_CERT_P12_BASE64 DIST_CERT_PASSWORD PROVISIONING_PROFILE_BASE64; do
  [[ -n "${!v:-}" ]] || missing+=("$v")
done
if (( ${#missing[@]} )); then
  echo "::error::Missing signing secrets: ${missing[*]}. Add them (see AGENTS.md, Release signing) or rerun with allow_auto_signing." >&2
  exit 1
fi
: "${KEYCHAIN:?KEYCHAIN is not set}"
: "${KEYCHAIN_PASSWORD:?KEYCHAIN_PASSWORD is not set}"

umask 077
P12="$RUNNER_TEMP/dist.p12"
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PROFILE="$PROFILE_DIR/arinoa-ci.mobileprovision"
trap 'rm -f "$P12"' EXIT

printf '%s' "$DIST_CERT_P12_BASE64" | tr -d ' \r\n' | base64 --decode > "$P12"
security import "$P12" -k "$KEYCHAIN" -P "$DIST_CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

mkdir -p "$PROFILE_DIR"
printf '%s' "$PROVISIONING_PROFILE_BASE64" | tr -d ' \r\n' | base64 --decode > "$PROFILE"
PLIST="$RUNNER_TEMP/profile.plist"
security cms -D -i "$PROFILE" > "$PLIST"
NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" "$PLIST")
UUID=$(/usr/libexec/PlistBuddy -c "Print :UUID" "$PLIST")
EXP=$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$PLIST")
rm -f "$PLIST"
echo "PROFILE_NAME=$NAME" >> "$GITHUB_ENV"
echo "==> Installed profile '$NAME' ($UUID), expires $EXP"
security find-identity -v -p codesigning "$KEYCHAIN" | grep -c "Apple Distribution" >/dev/null \
  || { echo "::error::No Apple Distribution identity in the imported .p12" >&2; exit 1; }
echo "==> Distribution identity ready"
