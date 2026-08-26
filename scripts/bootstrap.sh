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
trap 'rm -f -- "$password_file" "$curl_config"' EXIT
chmod 0600 "$password_file"
chmod 0600 "$curl_config"
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
  curl --fail-with-body --silent --show-error \
    --config "$curl_config" \
    --connect-timeout 5 \
    --max-time 30 \
    --retry 60 \
    --retry-delay 1 \
    --retry-max-time 120 \
    --retry-all-errors \
    --header 'Content-Type: application/json' \
    --data-binary @- \
    "${runtime_url}/v1/capabilities/${capability}/invoke" >/dev/null
}

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
