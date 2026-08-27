#!/usr/bin/env bash
set -euo pipefail
output="${1:-runtime/node-security}"; mkdir -p "$output"; umask 077
openssl ecparam -name prime256v1 -genkey -noout -out "$output/task-signing-key.pem"
openssl ec -in "$output/task-signing-key.pem" -pubout -out "$output/task-signing-public.pem"
if [[ -n "${BUNDLE_PUBLISHER_PUBLIC_KEY_FILE:-}" ]]; then
  cp "${BUNDLE_PUBLISHER_PUBLIC_KEY_FILE}" "$output/bundle-signing-public.pem"
elif [[ -n "${BUNDLE_PUBLISHER_PUBLIC_KEY_PEM:-}" ]]; then
  printf '%s' "${BUNDLE_PUBLISHER_PUBLIC_KEY_PEM}" > "$output/bundle-signing-public.pem"
else
  openssl ecparam -name prime256v1 -genkey -noout -out "$output/bundle-signing-key.pem"
  openssl ec -in "$output/bundle-signing-key.pem" -pubout -out "$output/bundle-signing-public.pem"
fi
openssl req -x509 -newkey rsa:3072 -sha256 -days 365 -nodes -subj '/CN=Murchalka Node CA/O=Murchalka' -keyout "$output/node-ca-key.pem" -out "$output/node-ca.pem"
openssl pkcs12 -export -out "$output/node-ca.pfx" -inkey "$output/node-ca-key.pem" -in "$output/node-ca.pem" -passout "pass:${NODE_CA_PASSWORD:?NODE_CA_PASSWORD is required}"
openssl req -newkey rsa:3072 -nodes -subj '/CN=node-controller/O=Murchalka' -keyout "$output/node-controller-key.pem" -out "$output/node-controller.csr"
cat > "$output/node-controller.ext" <<'EOF'
subjectAltName=DNS:node-controller,DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF
openssl x509 -req -in "$output/node-controller.csr" -CA "$output/node-ca.pem" -CAkey "$output/node-ca-key.pem" -CAcreateserial -days 30 -sha256 -extfile "$output/node-controller.ext" -out "$output/node-controller.pem"
openssl pkcs12 -export -out "$output/node-controller.pfx" -inkey "$output/node-controller-key.pem" -in "$output/node-controller.pem" -certfile "$output/node-ca.pem" -passout "pass:${NODE_CA_PASSWORD}"
public_key="$(< "$output/bundle-signing-public.pem")"
jq -n --arg publicKeyPem "$public_key" --arg keyId "${MURCHALKA_BUNDLE_SIGNING_KEY_ID:-phase6-e2e}" '{publishers:{"dev.murchalka":{keys:{($keyId):{algorithm:"ecdsa-p256-sha256",publicKeyPem:$publicKeyPem}}}},grantAuthorities:{}}' > "$output/trusted-publishers.json"
chmod 0600 "$output"/*
