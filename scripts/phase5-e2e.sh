#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--password-stdin" || "$#" -ne 1 ]]; then
  echo "Usage: printf '%s\\n' '<password>' | phase5-e2e.sh --password-stdin" >&2
  exit 2
fi

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
web_root="$(cd -- "${MURCHALKA_WEB_ROOT:-${repository_root}/../murchalka-web}" && pwd)"
compose_files=(-f "${repository_root}/compose/compose.yaml")
runtime_services=(runtime web)
runtime_url="http://127.0.0.1:5078"
realtime_url="ws://127.0.0.1:5080/v1/realtime"
realtime_http_url="http://127.0.0.1:5080/v1/realtime"
if [[ "$(uname -s)" == "Darwin" ]]; then
  compose_files+=(-f "${repository_root}/compose/compose.macos.yaml")
  runtime_services+=(runtime-relay)
  runtime_url="http://127.0.0.1:15078"
  realtime_url="ws://127.0.0.1:15080/v1/realtime"
  realtime_http_url="http://127.0.0.1:15080/v1/realtime"
fi
compose=(docker compose --env-file "${repository_root}/.env" "${compose_files[@]}")
password_file="$(mktemp)"
evidence_file="$(mktemp)"
modules_file="$(mktemp)"
curl_config="$(mktemp)"
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "${status}" -ne 0 ]]; then
    "${compose[@]}" logs --no-color >&2 || true
  fi
  rm -f -- "${password_file}" "${evidence_file}" "${modules_file}" "${curl_config}"
  "${compose[@]}" down >/dev/null 2>&1 || true
  exit "${status}"
}
trap cleanup EXIT
chmod 0600 "${password_file}"
chmod 0600 "${evidence_file}"
chmod 0600 "${modules_file}"
chmod 0600 "${curl_config}"
password=""
IFS= read -r password || [[ -n "${password}" ]]
printf '%s\n' "${password}" > "${password_file}"
unset password
if [[ ! -s "${password_file}" ]]; then
  echo "A non-empty password must be supplied on standard input." >&2
  exit 2
fi
if [[ ! -f "${repository_root}/runtime/security/trusted-publishers.json" ]]; then
  echo "Run scripts/prepare-security.sh before the acceptance scenario." >&2
  exit 2
fi
if [[ ! -s "${repository_root}/runtime/security/admin-token" ]]; then
  echo "Administrative token is missing. Run scripts/prepare-security.sh before the acceptance scenario." >&2
  exit 2
fi
if ! find "${repository_root}/runtime/modules/inbox" -maxdepth 1 -name '*.murchalka' -print -quit | grep -q .; then
  echo "No module bundles were found in runtime/modules/inbox." >&2
  exit 2
fi

"${compose[@]}" up -d ollama
"${compose[@]}" exec -T ollama ollama pull "${MURCHALKA_OLLAMA_MODEL:-llama3.2:1b}"
"${compose[@]}" up -d "${runtime_services[@]}"

runtime_container="$("${compose[@]}" ps -q runtime)"
if [[ -z "${runtime_container}" ]]; then
  echo "Runtime container was not created." >&2
  exit 1
fi
for attempt in {1..180}; do
  if curl --fail --silent "${runtime_url}/health" >/dev/null; then
    break
  fi
  if [[ "$(docker inspect --format '{{.RestartCount}}' "${runtime_container}")" -gt 0 ]]; then
    echo "Runtime restarted before becoming ready." >&2
    exit 1
  fi
  if [[ "${attempt}" -eq 180 ]]; then
    echo "Runtime did not become ready." >&2
    exit 1
  fi
  sleep 1
done

for attempt in {1..60}; do
  if curl --fail --silent http://127.0.0.1:8080/ >/dev/null; then
    break
  fi
  if [[ "${attempt}" -eq 60 ]]; then
    echo "Released Web container did not become ready." >&2
    exit 1
  fi
  sleep 1
done

MURCHALKA_RUNTIME_URL="${runtime_url}" "${repository_root}/scripts/bootstrap.sh" --password-stdin < "${password_file}"

admin_token="$(tr -d '\r\n' < "${repository_root}/runtime/security/admin-token")"
printf 'header = "Authorization: Bearer %s"\n' "${admin_token}" > "${curl_config}"
unset admin_token
expected_modules="$(find "${repository_root}/runtime/modules/inbox" -maxdepth 1 -name '*.murchalka' | wc -l | tr -d ' ')"
stable_checks=0
for attempt in {1..240}; do
  if curl --fail --silent --config "${curl_config}" --output "${modules_file}" "${runtime_url}/v1/modules" &&
    jq -e --argjson expected "${expected_modules}" 'length == $expected and all(.state == 14)' "${modules_file}" >/dev/null; then
    stable_checks=$((stable_checks + 1))
    if [[ "${stable_checks}" -ge 5 ]]; then
      break
    fi
  else
    stable_checks=0
  fi
  if [[ "${attempt}" -eq 240 ]]; then
    echo "Modules did not reach a stable Active state:" >&2
    jq '[.[] | select(.state != 14) | {moduleId, state, reasonCode}]' "${modules_file}" >&2 || true
    exit 1
  fi
  sleep 1
done

for attempt in {1..180}; do
  if curl --silent --output /dev/null --connect-timeout 1 --max-time 2 "${realtime_http_url}"; then
    break
  fi
  if [[ "${attempt}" -eq 180 ]]; then
    echo "Realtime endpoint did not become ready." >&2
    exit 1
  fi
  sleep 1
done

(
  cd -- "${web_root}"
  MURCHALKA_E2E_USERNAME="${MURCHALKA_USERNAME:-owner}" \
  MURCHALKA_E2E_PASSWORD="$(<"${password_file}")" \
  MURCHALKA_E2E_EVIDENCE="${evidence_file}" \
  MURCHALKA_E2E_BASE_URL="http://127.0.0.1:8080" \
  MURCHALKA_E2E_REALTIME_ENDPOINT="${realtime_url}" \
  npm run test:e2e
)

dotnet run \
  --project "${repository_root}/tools/Murchalka.Phase5.Acceptance/Murchalka.Phase5.Acceptance.csproj" \
  --configuration Release \
  -- --runtime "${runtime_url}" \
  --realtime "${realtime_url}" \
  --username "${MURCHALKA_USERNAME:-owner}" \
  --admin-token-file "${repository_root}/runtime/security/admin-token" \
  --evidence "${evidence_file}" < "${password_file}"
