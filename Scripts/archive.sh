#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH="build/Uttr.xcarchive"

echo "==> Archiving..."
xcodebuild archive \
    -project Uttr.xcodeproj \
    -scheme Uttr \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS=arm64

echo "==> Exporting..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath build/export \
    -exportOptionsPlist Scripts/ExportOptions.plist

echo "==> Archive complete: $ARCHIVE_PATH"
