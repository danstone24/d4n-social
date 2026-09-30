#!/bin/sh
# Mint a short-lived App Store Connect API JWT (ES256) with openssl only.
# Usage: asc-token.sh            -> prints token (20 min)
# Env:   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (default ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8)
set -eu
KEY_ID="${ASC_KEY_ID:?set ASC_KEY_ID}"
ISSUER="${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8}"
b64url() { openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }
NOW=$(date +%s)
EXP=$((NOW + 1200))
HEADER=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$KEY_ID" | b64url)
PAYLOAD=$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"appstoreconnect-v1"}' "$ISSUER" "$NOW" "$EXP" | b64url)
# openssl emits a DER signature; the JWT needs raw r||s (64 bytes).
DER=$(printf '%s.%s' "$HEADER" "$PAYLOAD" | openssl dgst -sha256 -sign "$KEY_PATH" -binary | openssl asn1parse -inform DER 2>/dev/null | awk -F: '/INTEGER/ {print $4}')
R=$(echo "$DER" | sed -n 1p); S=$(echo "$DER" | sed -n 2p)
R=$(printf '%64s' "$R" | tr ' ' 0 | tail -c 64); S=$(printf '%64s' "$S" | tr ' ' 0 | tail -c 64)
SIG=$(printf '%s%s' "$R" "$S" | xxd -r -p | b64url)
printf '%s.%s.%s\n' "$HEADER" "$PAYLOAD" "$SIG"
