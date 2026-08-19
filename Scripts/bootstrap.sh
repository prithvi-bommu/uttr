#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing git hooks..."
git config core.hooksPath .githooks

echo "==> Resolving Swift packages..."
xcodebuild -project Uttr.xcodeproj -scheme Uttr -resolvePackageDependencies

echo "==> Bootstrap complete."
