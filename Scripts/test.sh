#!/usr/bin/env bash
set -euo pipefail

echo "==> Running unit tests..."
xcodebuild test \
    -project Uttr.xcodeproj \
    -scheme Uttr \
    -destination "platform=macOS,arch=arm64" \
    -resultBundlePath build/TestResults.xcresult \
    | xcbeautify 2>/dev/null || true

echo "==> Tests complete."
