#!/bin/bash
#
# Create the self-signed code-signing certificate "Network Sentinel Code Signing"
# (10 years), import it into the login keychain for codesign, and export it as
# a .p12 for GitHub Actions.
#
# Every build signed with the same certificate keeps the same designated
# requirement (bundle ID + certificate hash), so the Keychain remembers
# 「始终允许」 across rebuilds and new versions. Run this once; keep the .p12.
#
# The .p12 password is random and goes to the login keychain as the generic
# password "Network Sentinel signing p12". It is never printed.
#
# Usage: scripts/make-signing-cert.sh <folder for the .p12>
#
set -euo pipefail

NAME="Network Sentinel Code Signing"
OUT_DIR="$1"
P12="$OUT_DIR/NetworkSentinel-signing.p12"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "error: \"$NAME\" is already in the keychain" >&2
    exit 1
fi
if [ -e "$P12" ]; then
    echo "error: $P12 already exists" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null

PASSWORD="$(openssl rand -hex 24)"
mkdir -p "$OUT_DIR"
openssl pkcs12 -export -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$P12" -passout "pass:$PASSWORD"
chmod 600 "$P12"

security import "$P12" -k "$LOGIN_KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
security add-generic-password -U -a "$USER" -s "Network Sentinel signing p12" -w "$PASSWORD" "$LOGIN_KEYCHAIN"

echo "Imported \"$NAME\" into the login keychain"
echo "Wrote $P12 (password in the keychain item \"Network Sentinel signing p12\")"
