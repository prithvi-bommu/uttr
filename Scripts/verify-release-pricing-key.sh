#!/usr/bin/env bash
set -euo pipefail

config_file="Uttr/Resources/PricingConfig.json"

if ! [ -f "$config_file" ]; then
    echo "Pricing configuration is missing: $config_file" >&2
    exit 1
fi

if /usr/bin/grep -Eq '"revenueCatAPIKey"[[:space:]]*:[[:space:]]*"test_' "$config_file"; then
    echo "Release builds cannot use a RevenueCat test_ API key." >&2
    exit 1
fi
