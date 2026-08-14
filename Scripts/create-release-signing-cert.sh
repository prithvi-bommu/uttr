#!/usr/bin/env bash
set -euo pipefail

# Creates the long-lived self-signed identity used by the no-membership
# Sparkle release channel. Keep the generated .p12 and password private.
OUT_DIR="${1:-build/uttr-release-signing}"
PASSWORD="${UTTR_SIGNING_CERTIFICATE_PASSWORD:-}"

if [[ -z "$PASSWORD" ]]; then
    read -r -s -p "Password for the exported signing identity: " PASSWORD
    printf '\n'
fi

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$OUT_DIR/uttr-release-signing.key.pem" \
    -out "$OUT_DIR/uttr-release-signing.cert.pem" \
    -subj "/CN=Uttr Release Signing/O=Uttr" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning"

openssl pkcs12 -export -legacy \
    -out "$OUT_DIR/Uttr-Release-Signing.p12" \
    -inkey "$OUT_DIR/uttr-release-signing.key.pem" \
    -in "$OUT_DIR/uttr-release-signing.cert.pem" \
    -name "Uttr Release Signing" \
    -passout "pass:$PASSWORD"

chmod 600 "$OUT_DIR"/*
echo "Created $OUT_DIR/Uttr-Release-Signing.p12"
echo "Store the p12 password separately, then add these GitHub secrets:"
echo "  UTTR_SIGNING_CERTIFICATE_P12_BASE64 = base64 -i $OUT_DIR/Uttr-Release-Signing.p12"
echo "  UTTR_SIGNING_CERTIFICATE_P12_PASSWORD = the password you entered"
