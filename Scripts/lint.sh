#!/usr/bin/env bash
set -euo pipefail

if command -v swiftlint &>/dev/null; then
    swiftlint lint --strict
elif [ -f ".build/swiftlint/swiftlint" ]; then
    .build/swiftlint/swiftlint lint --strict
else
    echo "warning: SwiftLint not installed. Skipping lint."
    exit 0
fi
