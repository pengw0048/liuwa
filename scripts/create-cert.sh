#!/bin/bash
# Create a self-signed "Liuwa Dev" code signing certificate.
# This ensures TCC permissions (Accessibility, Microphone, Screen Recording)
# persist across rebuilds — macOS matches the signing identity, not the binary hash.
#
# Only needs to be run once per machine.
set -euo pipefail

CERT_NAME="Liuwa Dev"

# Check if already exists
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "'$CERT_NAME' certificate already exists in keychain."
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    exit 0
fi

echo "Creating self-signed code signing certificate '$CERT_NAME'..."

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# OpenSSL config for code signing
cat > "$TMPDIR/cert.conf" << 'EOF'
[ req ]
default_bits       = 2048
distinguished_name = req_dn
x509_extensions    = codesign
prompt             = no

[ req_dn ]
CN = Liuwa Dev

[ codesign ]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
EOF

# Generate certificate + key
openssl req -x509 -newkey rsa:2048 \
    -keyout "$TMPDIR/key.pem" -out "$TMPDIR/cert.pem" \
    -days 3650 -nodes \
    -config "$TMPDIR/cert.conf" 2>/dev/null

# Package as .p12
openssl pkcs12 -export \
    -out "$TMPDIR/liuwa.p12" \
    -inkey "$TMPDIR/key.pem" -in "$TMPDIR/cert.pem" \
    -passout pass:liuwa -legacy 2>/dev/null

# Import into login keychain
security import "$TMPDIR/liuwa.p12" \
    -k ~/Library/Keychains/login.keychain-db \
    -T /usr/bin/codesign \
    -P "liuwa"

# Trust for code signing (may prompt for password)
echo "Trusting certificate for code signing (may require your login password)..."
security add-trusted-cert -d -r trustRoot -p codeSign \
    -k ~/Library/Keychains/login.keychain-db "$TMPDIR/cert.pem"

echo ""
echo "Done! Verifying..."
security find-identity -v -p codesigning | grep "$CERT_NAME"
echo ""
echo "'$CERT_NAME' is ready. bundle.sh will use it automatically."
