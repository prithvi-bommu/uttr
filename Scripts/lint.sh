#!/usr/bin/env bash
set -euo pipefail

if command -v swiftlint &>/dev/null; then
    swiftlint lint --strict
elif [ -f ".build/swiftlint/swiftlint" ]; then
    .build/swiftlint/swiftlint lint --strict
else
    echo "error: SwiftLint is required. Install it with: brew install swiftlint" >&2
    exit 127
fi
