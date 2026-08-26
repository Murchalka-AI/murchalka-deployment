#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--password-stdin" || "$#" -ne 1 ]]; then
  echo "Usage: printf '%s\\n' '<password>' | phase5-e2e.sh --password-stdin" >&2
  exit 2
fi

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
web_root="$(cd -- "${MURCHALKA_WEB_ROOT:-${repository_root}/../murchalka-web}" && pwd)"
compose=(docker compose --env-file "${repository_root}/.env" -f "${repository_root}/compose/compose.yaml")
password_file="$(mktemp)"
evidence_file="$(mktemp)"
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "${status}" -ne 0 ]]; then
    "${compose[@]}" logs --no-color >&2 || true
  fi
  rm -f -- "${password_file}" "${evidence_file}"
  "${compose[@]}" down >/dev/null 2>&1 || true
  exit "${status}"
}
trap cleanup EXIT
chmod 0600 "${password_file}"
chmod 0600 "${evidence_file}"
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
"${compose[@]}" exec -T ollama ollama pull "${MURCHALKA_OLLAMA_MODEL:-llama3.2}"
"${compose[@]}" up -d runtime web

runtime_container="$("${compose[@]}" ps -q runtime)"
if [[ -z "${runtime_container}" ]]; then
  echo "Runtime container was not created." >&2
  exit 1
fi
for attempt in {1..180}; do
  if curl --fail --silent http://127.0.0.1:5078/health >/dev/null; then
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

"${repository_root}/scripts/bootstrap.sh" --password-stdin < "${password_file}"

(
  cd -- "${web_root}"
  MURCHALKA_E2E_USERNAME="${MURCHALKA_USERNAME:-owner}" \
  MURCHALKA_E2E_PASSWORD="$(<"${password_file}")" \
  MURCHALKA_E2E_EVIDENCE="${evidence_file}" \
  MURCHALKA_E2E_BASE_URL="http://127.0.0.1:8080" \
  npm run test:e2e
)

dotnet run \
  --project "${repository_root}/tools/Murchalka.Phase5.Acceptance/Murchalka.Phase5.Acceptance.csproj" \
  --configuration Release \
  -- --username "${MURCHALKA_USERNAME:-owner}" \
  --admin-token-file "${repository_root}/runtime/security/admin-token" \
  --evidence "${evidence_file}" < "${password_file}"
