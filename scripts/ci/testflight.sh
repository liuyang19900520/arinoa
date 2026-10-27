#!/usr/bin/env bash
# Archive Arinoa, sign it automatically with an App Store Connect API key,
# and upload it to App Store Connect, where it lands in TestFlight. Nothing is
# submitted for review.
#
# Environment:
#   ASC_KEY_ID      API key ID
#   ASC_ISSUER_ID   issuer ID
#   ASC_KEY_P8      the .p8 private key, either as the PEM text or base64 of it
#   BUILD_NUMBER    CFBundleVersion for this build (must be higher than any
#                   already uploaded for this version)
#   DRY_RUN=1       optional: archive and export locally, but don't upload
set -euo pipefail

cd "$(dirname "$0")/../.."

# The Xcode project is generated from project.yml and not committed.
command -v xcodegen >/dev/null || { echo "xcodegen is not installed (brew install xcodegen)" >&2; exit 1; }
xcodegen generate

TEAM_ID=3T7MJA53W9
SCHEME=BeautyCam
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/arinoa-release"

: "${ASC_KEY_ID:?ASC_KEY_ID is not set}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is not set}"
: "${ASC_KEY_P8:?ASC_KEY_P8 is not set}"
: "${BUILD_NUMBER:?BUILD_NUMBER is not set}"

rm -rf "$WORK"
mkdir -p "$WORK"
KEY_PATH="$WORK/AuthKey_${ASC_KEY_ID}.p8"
trap 'rm -f "$KEY_PATH"' EXIT

# --- API key ---------------------------------------------------------------
scripts/ci/write-asc-key.sh "$KEY_PATH"

AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

# --- Archive ---------------------------------------------------------------
echo "==> Archiving build $BUILD_NUMBER"
xcodebuild archive \
  -project BeautyCam.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$WORK/Arinoa.xcarchive" \
  "${AUTH[@]}" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -quiet

# --- Export (and upload) ---------------------------------------------------
# destination=upload sends the build straight to App Store Connect; export
# would only write the .ipa locally.
DESTINATION=upload
[[ "${DRY_RUN:-}" == 1 ]] && DESTINATION=export

cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <!-- Keep the build number this script chose. -->
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

echo "==> Exporting ($DESTINATION)"
xcodebuild -exportArchive \
  -archivePath "$WORK/Arinoa.xcarchive" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$WORK/export" \
  "${AUTH[@]}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$WORK/Arinoa.xcarchive/Info.plist")
if [[ "$DESTINATION" == upload ]]; then
  echo "==> Uploaded Arinoa $VERSION ($BUILD_NUMBER). It appears in TestFlight once App Store Connect finishes processing."
else
  echo "==> Dry run: exported Arinoa $VERSION ($BUILD_NUMBER) to $WORK/export, not uploaded."
fi
