#!/usr/bin/env bash
set -euo pipefail

if command -v swiftlint &>/dev/null; then
    swiftlint_binary=$(command -v swiftlint)
elif [ -f ".build/swiftlint/swiftlint" ]; then
    swiftlint_binary=".build/swiftlint/swiftlint"
else
    echo "error: SwiftLint is required. Install it with: brew install swiftlint" >&2
    exit 127
fi

# SwiftLint baselines contain absolute file URLs. Materialize the checked-in
# template for this checkout so the lint-debt ratchet works locally and in CI.
runtime_baseline=$(mktemp "${TMPDIR:-/tmp}/uttr-swiftlint-baseline.XXXXXX")
trap 'rm -f "$runtime_baseline"' EXIT
repository_root=$(pwd -P)
escaped_root=${repository_root//&/\\&}
sed "s|__REPO_ROOT__|$escaped_root|g" \
    .swiftlint-baseline.template.json > "$runtime_baseline"

"$swiftlint_binary" lint --strict --baseline "$runtime_baseline"
