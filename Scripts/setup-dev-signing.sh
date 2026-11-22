#!/usr/bin/env bash
# Creates a self-signed code-signing identity for development builds, in a keychain
# of its own. macOS remembers privacy answers, such as access to Downloads, per code
# signature. An ad-hoc signature changes with every build, so without a stable
# identity macOS asks again after each rebuild.
#
# Run once; Scripts/run-dev-app.sh then signs with it. Nothing is added to the login
# keychain. To remove it: rm -rf ~/Library/Developer/Raker
set -euo pipefail

dir="${RAKER_SIGNING_DIR:-$HOME/Library/Developer/Raker}"
keychain="$dir/signing.keychain-db"
name="Raker Development"

if [[ -f "$keychain" && -f "$dir/password" ]]; then
    echo "Already set up: $keychain"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$dir"
chmod 700 "$dir"
rm -f "$keychain" "$dir/password"

cat > "$work/identity.cnf" <<EOF
[req]
distinguished_name = subject
x509_extensions = codesigning
prompt = no
[subject]
CN = $name
[codesigning]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# The system LibreSSL writes PKCS#12 files that `security import` reads.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/identity.cnf" \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -name "$name" -inkey "$work/key.pem" -in "$work/cert.pem" \
    -out "$work/identity.p12" -passout pass:import

password="$(/usr/bin/openssl rand -hex 24)"
(umask 077 && printf '%s' "$password" > "$dir/password")
security create-keychain -p "$password" "$keychain"
security import "$work/identity.p12" -k "$keychain" -P import -T /usr/bin/codesign >/dev/null
# Lets codesign use the key without asking.
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null

echo "Created the \"$name\" signing identity in $keychain"
