#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: make-dmg.sh <path-to-app>}"
VERSION="${2:?Usage: make-dmg.sh <path-to-app> <version>}"
DMG_NAME="Uttr-${VERSION}.dmg"
DMG_PATH="build/${DMG_NAME}"
STAGING="build/dmg-staging"

echo "==> Creating DMG..."

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Uttr" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING"

echo "==> Computing checksum..."
shasum -a 256 "$DMG_PATH" | tee "build/${DMG_NAME}.sha256"

echo "==> DMG created: $DMG_PATH"
