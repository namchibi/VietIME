#!/bin/sh
# One-time setup: creates a self-signed code-signing identity in its own
# keychain. Signing with a stable identity (instead of ad-hoc) lets macOS
# keep VietIME's Accessibility permission across rebuilds.
set -e

KEYCHAIN="$HOME/Library/Keychains/vietime-dev.keychain-db"
PASSWORD="vietime-dev"  # only guards this throwaway local dev key
NAME="VietIME Dev"

if [ -f "$KEYCHAIN" ]; then
    echo "Already set up: $KEYCHAIN"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout "pass:$PASSWORD"

security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"  # never auto-lock
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign
# Lets codesign use the key without a keychain password prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

# codesign only finds identities in keychains on the search list.
EXISTING=$(security list-keychains -d user | tr -d '"')
security list-keychains -d user -s $EXISTING "$KEYCHAIN"

echo "Created signing identity \"$NAME\" in $KEYCHAIN"
