#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: notarize.sh <path-to-app>}"

echo "==> Submitting for notarization..."
xcrun notarytool submit "$APP_PATH" \
    --keychain-profile "uttr-notarize" \
    --wait

echo "==> Stapling ticket..."
xcrun stapler staple "$APP_PATH"

echo "==> Verifying..."
spctl --assess --type execute --verbose "$APP_PATH"

echo "==> Notarization complete."
