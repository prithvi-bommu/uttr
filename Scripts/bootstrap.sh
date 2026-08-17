#!/usr/bin/env bash
set -euo pipefail

echo "==> Resolving Swift packages..."
xcodebuild -project Uttr.xcodeproj -scheme Uttr -resolvePackageDependencies

echo "==> Bootstrap complete."
