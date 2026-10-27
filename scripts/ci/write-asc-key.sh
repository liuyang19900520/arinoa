#!/usr/bin/env bash
# Write the App Store Connect API key from $ASC_KEY_P8 to the given path.
# The secret may hold the .p8 file as-is (PEM text) or base64 of that file.
set -euo pipefail

OUT="${1:?usage: write-asc-key.sh <output path>}"
: "${ASC_KEY_P8:?ASC_KEY_P8 is not set}"

umask 077
if [[ "$ASC_KEY_P8" == *"BEGIN PRIVATE KEY"* ]]; then
  # PEM text. Secrets pasted through some tools arrive with literal "\n"
  # instead of line breaks; turn those back into real ones.
  printf '%s\n' "$ASC_KEY_P8" | perl -pe 's/\\n/\n/g' > "$OUT"
else
  # base64, possibly wrapped across lines.
  if ! printf '%s' "$ASC_KEY_P8" | tr -d ' \r\n' | base64 --decode > "$OUT" 2>/dev/null; then
    echo "ASC_KEY_P8 is neither PEM text nor valid base64." >&2
    exit 1
  fi
fi

if ! openssl pkey -in "$OUT" -noout 2>/dev/null; then
  echo "ASC_KEY_P8 didn't decode to a readable private key. Paste the whole .p8 file, or base64 of it." >&2
  rm -f "$OUT"
  exit 1
fi
echo "==> API key ready"
