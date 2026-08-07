#!/usr/bin/env bash
# Builds a distributable Release DMG.
#
# Signing identity is auto-detected (see docs/DECISIONS.md ADR-010):
#   1. $UTTR_SIGN_IDENTITY            explicit override
#   2. "Developer ID Application"     the real cert, once M7 lands — used
#                                     automatically, no script change needed
#   3. "Uttr Dev Signing"             free self-signed cert; keeps TCC grants
#                                     stable across rebuilds on this machine
#   4. "-"                            ad-hoc fallback (permissions reset on
#                                     every rebuild; ADR-009 manual add applies)
#
# Recipients of non-Developer-ID builds must right-click -> Open on first
# launch, or run: xattr -d com.apple.quarantine /Applications/Uttr.app
# Notarized distribution (Scripts/notarize.sh) replaces that in M7.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build/release"
APP_PATH="${BUILD_DIR}/Build/Products/Release/Uttr.app"

resolve_sign_identity() {
    if [[ -n "${UTTR_SIGN_IDENTITY:-}" ]]; then
        echo "$UTTR_SIGN_IDENTITY"
        return
    fi
    local identities
    identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
    if grep -q "Developer ID Application" <<< "$identities"; then
        # Print the full identity name, e.g. "Developer ID Application: Jane Doe (TEAMID)"
        sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' <<< "$identities" | head -1
        return
    fi
    if grep -q "Uttr Dev Signing" <<< "$identities"; then
        echo "Uttr Dev Signing"
        return
    fi
    echo "-"
}

SIGN_IDENTITY="$(resolve_sign_identity)"

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

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> Ad-hoc signing (WARNING: TCC permission grants will reset on every rebuild)"
else
    echo "==> Signing with identity: ${SIGN_IDENTITY}"
fi
codesign --force --sign "$SIGN_IDENTITY" --identifier com.uttr.app "$APP_PATH"
codesign --verify --strict "$APP_PATH"
echo "==> Designated requirement:"
codesign -d -r- "$APP_PATH" 2>&1 | grep "designated" || true

echo "==> Packaging DMG..."
./Scripts/make-dmg.sh "$APP_PATH" "$VERSION"

DMG_PATH="build/Uttr-${VERSION}.dmg"
echo "==> Opening ${DMG_PATH} in Finder..."
open "$DMG_PATH"

echo ""
echo "Done. The DMG window is open — drag Uttr onto the Applications folder."
if [[ "$SIGN_IDENTITY" == "Uttr Dev Signing" ]]; then
    echo "Signed with the self-signed dev cert: permission grants persist across"
    echo "rebuilds ON THIS MACHINE. Other Macs still need right-click -> Open."
elif [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Ad-hoc signed: re-grant Mic/Input Monitoring/Accessibility after install."
fi
