#!/usr/bin/env bash
# Builds a distributable (ad-hoc signed) Release DMG.
#
# Until an Apple Developer ID certificate is available (M7), the app is
# ad-hoc signed: recipients must right-click -> Open on first launch, or run
#   xattr -d com.apple.quarantine /Applications/Uttr.app
# Signed + notarized distribution replaces this script's signing step in M7
# (see Scripts/notarize.sh and docs/RELEASE.md).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build/release"
APP_PATH="${BUILD_DIR}/Build/Products/Release/Uttr.app"

echo "==> Building Release (arm64)..."
xcodebuild \
    -project Uttr.xcodeproj \
    -scheme Uttr \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'platform=macOS,arch=arm64' \
    build

VERSION=$(defaults read "$(pwd)/${APP_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")
echo "==> Built Uttr.app version ${VERSION}"

echo "==> Ad-hoc signing (stable identifier for TCC grants)..."
codesign --force --deep --sign - --identifier com.uttr.app "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "==> Packaging DMG..."
./Scripts/make-dmg.sh "$APP_PATH" "$VERSION"

DMG_PATH="build/Uttr-${VERSION}.dmg"
echo "==> Opening ${DMG_PATH} in Finder..."
open "$DMG_PATH"

echo ""
echo "Done. The DMG window is open — drag Uttr onto the Applications folder."
echo "Recipients: drag Uttr to Applications, then right-click -> Open the"
echo "first time (unsigned build). Onboarding will request permissions on"
echo "first launch."
