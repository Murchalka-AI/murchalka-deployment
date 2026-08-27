#!/usr/bin/env bash
set -euo pipefail

: "${MURCHALKA_NODE_CONTROLLER_IMAGE:?Controller image is required}"
: "${MURCHALKA_NODE_RUNTIME_IMAGE:?Node Runtime image is required}"
: "${MURCHALKA_NODE_DIAGNOSTICS_BUNDLE:?Diagnostics bundle is required}"
: "${NODE_ADMIN_TOKEN:?Admin token is required}"
: "${NODE_CA_PASSWORD:?CA password is required}"

export COMPOSE_PROJECT_NAME="murchalka-phase6-e2e"
export NODE_ENROLLMENT_TOKEN="bootstrap-placeholder"
compose=(docker compose -f compose/compose.phase6.yaml)
security="runtime/node-security"
ca="${security}/node-ca.pem"
base="https://127.0.0.1:5090"
authorization="Authorization: Bearer ${NODE_ADMIN_TOKEN}"

teardown() {
  "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}

finish() {
  status=$?
  trap - EXIT
  if [[ "${status}" -ne 0 ]]; then
    "${compose[@]}" logs --no-color --tail 300 >&2 || true
  fi

  teardown
  exit "${status}"
}
trap finish EXIT
teardown
NODE_CA_PASSWORD="${NODE_CA_PASSWORD}" scripts/prepare-node-security.sh "${security}"
"${compose[@]}" config --quiet
"${compose[@]}" up -d node-controller

for _ in $(seq 1 90); do
  if curl --fail --silent --cacert "${ca}" "${base}/health" >/dev/null; then break; fi
  sleep 1
done
curl --fail --silent --cacert "${ca}" "${base}/health" >/dev/null

export NODE_ENROLLMENT_TOKEN
NODE_ENROLLMENT_TOKEN="$(curl --fail --silent --cacert "${ca}" -H "${authorization}" -X POST "${base}/v1/admin/enrollment-tokens" | jq -er '.token')"
export NODE_ENROLLMENT_TOKEN
"${compose[@]}" up -d node

request_id=""
for _ in $(seq 1 90); do
  request_id="$(curl --fail --silent --cacert "${ca}" -H "${authorization}" "${base}/v1/admin/enrollments" | jq -er '.[0].requestId // empty')" || true
  if [[ -n "${request_id}" ]]; then break; fi
  sleep 1
done
test -n "${request_id}"
curl --fail --silent --cacert "${ca}" -H "${authorization}" -X POST "${base}/v1/admin/enrollments/${request_id}/approve?nodeId=node-e2e" >/dev/null

for _ in $(seq 1 90); do
  state="$(curl --fail --silent --cacert "${ca}" -H "${authorization}" "${base}/v1/admin/nodes" | jq -r '.[] | select(.nodeId == "node-e2e") | .state')"
  if [[ "${state}" == "connected" || "${state}" == "Connected" || "${state}" == "2" ]]; then break; fi
  sleep 1
done
[[ "${state}" =~ ^(connected|Connected|2)$ ]]

deployment_id="$(curl --fail --silent --cacert "${ca}" -H "${authorization}" -H 'Content-Type: application/vnd.murchalka.bundle' --data-binary "@${MURCHALKA_NODE_DIAGNOSTICS_BUNDLE}" "${base}/v1/admin/nodes/node-e2e/bundles" | jq -er '.deploymentId')"
provider_instance=""
for _ in $(seq 1 120); do
  status="$(curl --silent --cacert "${ca}" -H "${authorization}" "${base}/v1/admin/deployments/${deployment_id}" | jq -r '.[0].state // empty')"
  provider_instance="$(curl --fail --silent --cacert "${ca}" -H "${authorization}" "${base}/v1/admin/nodes" | jq -r '.[] | select(.nodeId == "node-e2e") | .descriptor.capabilities[]? | select(.capabilityId == "node.diagnostics.echo") | .providerInstance')"
  if [[ -n "${provider_instance}" && ( "${status}" == "active" || "${status}" == "Active" || "${status}" == "4" ) ]]; then break; fi
  sleep 1
done
test -n "${provider_instance}"
[[ "${status}" =~ ^(active|Active|4)$ ]]

task_request="$(jq -n --arg instance "${provider_instance}" '{nodeId:"node-e2e",consumerModuleId:"dev.murchalka.node-controller",providerModuleId:"dev.murchalka.node-diagnostics",moduleVersion:"0.3.2",capabilityId:"node.diagnostics.echo",capabilityVersion:"1.0.0",providerInstance:$instance,actorReference:"person:e2e",purpose:"diagnostics",arguments:{message:"phase6"},allowedPaths:[],allowedNetwork:[],resourceBudget:{cpuMillis:500,memoryBytes:134217728,outputBytes:4096},lifetime:"00:00:30",idempotencyKey:"phase6-e2e",traceId:"phase6-e2e",policyRevision:1}')"
task_id="$(curl --fail --silent --cacert "${ca}" -H "${authorization}" -H 'Content-Type: application/json' --data "${task_request}" "${base}/v1/admin/tasks" | jq -er '.taskId')"
for _ in $(seq 1 60); do
  result="$(curl --silent --cacert "${ca}" -H "${authorization}" "${base}/v1/admin/tasks/${task_id}")"
  task_state="$(jq -r '.state // empty' <<<"${result}")"
  if [[ "${task_state}" =~ ^(succeeded|Succeeded|failed|Failed|rejected|Rejected|cancelled|Cancelled|2|3|4|5|6)$ ]]; then break; fi
  sleep 1
done
if ! jq -e '(.state == "succeeded") or (.state == "Succeeded") or (.state == 3)' <<<"${result}" >/dev/null; then
  echo "Node task did not succeed:" >&2
  jq . <<<"${result}" >&2
  exit 1
fi
jq -e '.payload.echo.message == "phase6"' <<<"${result}" >/dev/null

curl --fail --silent --cacert "${ca}" -H "${authorization}" -X POST "${base}/v1/admin/nodes/node-e2e/revoke" >/dev/null
sleep 3
revoked="$(curl --fail --silent --cacert "${ca}" -H "${authorization}" "${base}/v1/admin/nodes" | jq -r '.[] | select(.nodeId == "node-e2e") | .state')"
[[ "${revoked}" =~ ^(revoked|Revoked|4)$ ]]
if curl --fail --silent --cacert "${ca}" -H "${authorization}" -H 'Content-Type: application/json' --data "${task_request}" "${base}/v1/admin/tasks" >/dev/null; then
  echo "A revoked Node accepted a new task." >&2
  exit 1
fi

echo "Phase 6 E2E passed: enroll, approve, connect, distribute, activate, execute, revoke, and deny."
