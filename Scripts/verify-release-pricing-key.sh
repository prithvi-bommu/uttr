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

# Web Billing checkout is inert without these. A release build that ships them
# empty would show a paywall whose buttons cannot open checkout.
for key in webPurchaseLink customerPortalLink; do
    if /usr/bin/grep -Eq "\"${key}\"[[:space:]]*:[[:space:]]*\"\"" "$config_file"; then
        echo "Release builds require a non-empty ${key} in ${config_file}." >&2
        exit 1
    fi
done
