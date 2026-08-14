#!/usr/bin/env bash
set -euo pipefail

echo "==> Running unit tests..."
mkdir -p build
rm -rf build/TestResults.xcresult

test_command=(
    xcodebuild test
    -project Uttr.xcodeproj
    -scheme Uttr
    -destination "platform=macOS,arch=arm64"
    -resultBundlePath build/TestResults.xcresult
)

if command -v xcbeautify &>/dev/null; then
    "${test_command[@]}" | xcbeautify
else
    "${test_command[@]}"
fi

echo "==> Tests complete."
