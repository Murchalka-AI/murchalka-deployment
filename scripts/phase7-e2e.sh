#!/usr/bin/env bash
set -euo pipefail

for tool in curl docker jq sha256sum; do command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 2; }; done
: "${MURCHALKA_RUNTIME_IMAGE:?MURCHALKA_RUNTIME_IMAGE is required}"
: "${PHASE7_BUNDLE_DIR:?PHASE7_BUNDLE_DIR is required}"
: "${PHASE7_SECURITY_DIR:?PHASE7_SECURITY_DIR is required}"
[[ -d "${PHASE7_BUNDLE_DIR}" && -d "${PHASE7_SECURITY_DIR}" ]] || { echo "Phase 7 bundle and security directories must exist." >&2; exit 2; }
[[ "$(find "${PHASE7_BUNDLE_DIR}" -maxdepth 1 -type f -name '*.murchalka' | wc -l | tr -d ' ')" == 1 ]] || { echo "Exactly one diagnostics bundle is required." >&2; exit 2; }

repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose=(docker compose --project-name murchalka-phase7-acceptance -f "${repository}/compose/compose.phase7.yaml")
cleanup() { "${compose[@]}" logs --no-color phase7-runtime 2>/dev/null || true; "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT
"${compose[@]}" up --detach phase7-runtime

runtime=http://127.0.0.1:15078
for _ in {1..90}; do if curl --fail --silent "${runtime}/health" >/dev/null; then break; fi; sleep 1; done
curl --fail --silent "${runtime}/health" | jq -e '.runtimeVersion == "0.4.1"' >/dev/null
catalog="$(curl --fail --silent "${runtime}/client/v1/catalog")"
revision="$(jq -er '.revision' <<<"${catalog}")"
jq -e '.entries | length == 1 and .[0].extensionId == "client.diagnostics" and .[0].targets == ["desktop", "web"]' <<<"${catalog}" >/dev/null
artifact_digest="$(jq -er '.entries[0].artifactDigest' <<<"${catalog}")"
artifact_url="$(jq -er '.entries[0].artifactUrl' <<<"${catalog}")"
artifact_file="$(mktemp)"
curl --fail --silent "${runtime}${artifact_url}" --output "${artifact_file}"
[[ "sha256:$(sha256sum "${artifact_file}" | cut -d' ' -f1)" == "${artifact_digest}" ]]

admin_token="$(tr -d '\r\n' < "${PHASE7_SECURITY_DIR}/admin-token")"
action='{"payload":{"extensionId":"client.diagnostics","actionId":"client.diagnostics.run","payload":{"message":"Phase 7"}},"idempotencyKey":"phase7-acceptance","scope":{"personId":"phase7-person"}}'
curl --fail --silent --header "Authorization: Bearer ${admin_token}" --header 'Content-Type: application/json' --data "${action}" "${runtime}/v1/capabilities/client.diagnostics.action/invoke" | jq -e '.accepted == true and .diagnosticValue == 7' >/dev/null

if [[ -n "${PHASE7_WEB_DIR:-}" ]]; then
  [[ -d "${PHASE7_WEB_DIR}" ]] || { echo "PHASE7_WEB_DIR must identify the built Web repository." >&2; exit 2; }
  (
    cd "${PHASE7_WEB_DIR}"
    PHASE7_RUNTIME_ORIGIN="${runtime}" PHASE7_ADMIN_TOKEN="${admin_token}" npx playwright test e2e/phase7-runtime.spec.ts
  )
fi

if [[ -n "${PHASE7_DESKTOP_DIR:-}" ]]; then
  command -v xvfb-run >/dev/null || { echo "xvfb-run is required for Desktop acceptance." >&2; exit 2; }
  [[ -d "${PHASE7_DESKTOP_DIR}" ]] || { echo "PHASE7_DESKTOP_DIR must identify the built Desktop repository." >&2; exit 2; }
  (
    cd "${PHASE7_DESKTOP_DIR}"
    PHASE7_RUNTIME_ORIGIN="${runtime}" PHASE7_ADMIN_TOKEN="${admin_token}" xvfb-run -a npx playwright test e2e/phase7.spec.ts
  )
fi

curl --fail --silent --request POST --header "Authorization: Bearer ${admin_token}" "${runtime}/v1/modules/dev.murchalka.client-diagnostics/disable" >/dev/null
disabled="$(curl --fail --silent "${runtime}/client/v1/catalog")"
jq -e --argjson revision "${revision}" '.revision > $revision and (.entries | length == 0)' <<<"${disabled}" >/dev/null
if curl --silent --fail "${runtime}${artifact_url}" >/dev/null; then echo "Disabled artifact remained downloadable." >&2; exit 1; fi

disabled_revision="$(jq -er '.revision' <<<"${disabled}")"
curl --fail --silent --request POST --header "Authorization: Bearer ${admin_token}" "${runtime}/v1/modules/dev.murchalka.client-diagnostics/enable" >/dev/null
for _ in {1..30}; do
  restored="$(curl --fail --silent "${runtime}/client/v1/catalog")"
  if jq -e --argjson revision "${disabled_revision}" '.revision > $revision and (.entries | length == 1)' <<<"${restored}" >/dev/null; then break; fi
  sleep 1
done
jq -e --argjson revision "${disabled_revision}" '.revision > $revision and .entries[0].extensionId == "client.diagnostics"' <<<"${restored}" >/dev/null
echo "Phase 7 Runtime acceptance passed."
