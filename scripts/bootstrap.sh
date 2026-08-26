#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--password-stdin" || "$#" -ne 1 ]]; then
  echo "Usage: printf '%s\\n' '<password>' | bootstrap.sh --password-stdin" >&2
  exit 2
fi

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_url="${MURCHALKA_RUNTIME_URL:-http://127.0.0.1:5078}"
person_id="${MURCHALKA_PERSON_ID:-person-owner}"
person_name="${MURCHALKA_PERSON_NAME:-Local Owner}"
character_id="${MURCHALKA_CHARACTER_ID:-default}"
character_name="${MURCHALKA_CHARACTER_NAME:-Murchalka}"
character_description="${MURCHALKA_CHARACTER_DESCRIPTION:-A thoughtful local conversational companion.}"
system_prompt="${MURCHALKA_SYSTEM_PROMPT:-Be helpful, honest, warm, and concise.}"
username="${MURCHALKA_USERNAME:-owner}"
admin_token_file="${MURCHALKA_ADMIN_TOKEN_FILE:-${repository_root}/runtime/security/admin-token}"

case "$runtime_url" in
  http://127.0.0.1:*|http://localhost:*|http://\[::1\]:*) ;;
  *) echo "MURCHALKA_RUNTIME_URL must use an explicit loopback HTTP endpoint." >&2; exit 2 ;;
esac

password_file="$(mktemp)"
curl_config="$(mktemp)"
capabilities_file="$(mktemp)"
modules_file="$(mktemp)"
response_file="$(mktemp)"
trap 'rm -f -- "$password_file" "$curl_config" "$capabilities_file" "$modules_file" "$response_file"' EXIT
chmod 0600 "$password_file" "$curl_config" "$capabilities_file" "$modules_file" "$response_file"
IFS= read -r password
printf '%s' "$password" > "$password_file"
unset password
if [[ ! -s "$password_file" ]]; then
  echo "A non-empty password must be supplied on standard input." >&2
  exit 2
fi
if [[ ! -s "$admin_token_file" ]]; then
  echo "Administrative token file '$admin_token_file' is missing. Run prepare-security.sh first." >&2
  exit 2
fi
admin_token="$(tr -d '\r\n' < "$admin_token_file")"
printf 'header = "Authorization: Bearer %s"\n' "$admin_token" > "$curl_config"
unset admin_token

invoke() {
  local capability="$1"
  local status_code
  if ! status_code="$(curl --silent --show-error \
      --config "$curl_config" \
      --connect-timeout 5 \
      --max-time 30 \
      --output "$response_file" \
      --write-out '%{http_code}' \
      --header 'Content-Type: application/json' \
      --data-binary @- \
      "${runtime_url}/v1/capabilities/${capability}/invoke")"; then
    echo "Administrative invocation of '${capability}' failed at the transport layer." >&2
    return 1
  fi
  if [[ ! "${status_code}" =~ ^2[0-9][0-9]$ ]]; then
    echo "Administrative invocation of '${capability}' failed with HTTP ${status_code}:" >&2
    cat "$response_file" >&2
    echo >&2
    return 1
  fi
}

wait_for_bootstrap_capabilities() {
  local required='["people.directory","character.identity","auth.local"]'
  for attempt in {1..120}; do
    if curl --fail --silent --show-error \
        --config "$curl_config" \
        --connect-timeout 5 \
        --max-time 10 \
        --output "$capabilities_file" \
        "${runtime_url}/v1/capabilities" &&
      jq -e --argjson required "$required" '$required - [.[].id] | length == 0' "$capabilities_file" >/dev/null; then
      return 0
    fi
    sleep 1
  done

  echo "Bootstrap capabilities did not become available:" >&2
  jq -r --argjson required "$required" '$required - [.[].id] | .[]' "$capabilities_file" >&2 || true
  if curl --fail --silent --show-error \
      --config "$curl_config" \
      --connect-timeout 5 \
      --max-time 10 \
      --output "$modules_file" \
      "${runtime_url}/v1/modules"; then
    jq . "$modules_file" >&2 || cat "$modules_file" >&2
  fi
  return 1
}

wait_for_bootstrap_capabilities

jq -cn \
  --arg personId "$person_id" \
  --arg displayName "$person_name" \
  '{payload:{operation:"create",personId:$personId,displayName:$displayName,externalIdentifiers:{}},idempotencyKey:"bootstrap-person-v1"}' \
  | invoke people.directory

jq -cn \
  --arg characterId "$character_id" \
  --arg displayName "$character_name" \
  --arg description "$character_description" \
  --arg systemPrompt "$system_prompt" \
  '{payload:{operation:"set",characterId:$characterId,displayName:$displayName,description:$description,systemPrompt:$systemPrompt},idempotencyKey:"bootstrap-character-v1"}' \
  | invoke character.identity

jq -cn \
  --arg username "$username" \
  --arg personId "$person_id" \
  --rawfile password "$password_file" \
  '{payload:{operation:"register",username:$username,password:$password,personId:$personId,roles:["admin"]},idempotencyKey:"bootstrap-auth-v1"}' \
  | invoke auth.local

echo "Bootstrapped person '${person_id}', character '${character_id}', and local user '${username}'."
