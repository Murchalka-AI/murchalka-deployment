#!/usr/bin/env bash
set -euo pipefail

trap 'status=$?; echo "Phase 8 acceptance failed at line ${LINENO} (exit ${status})." >&2' ERR

for tool in curl docker jq unzip zip; do command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 2; }; done
: "${MURCHALKA_RUNTIME_IMAGE:?MURCHALKA_RUNTIME_IMAGE is required}"
: "${PHASE8_RUNTIME_VERSION:?PHASE8_RUNTIME_VERSION is required}"
: "${PHASE8_GATEWAY_VERSION:?PHASE8_GATEWAY_VERSION is required}"
: "${PHASE8_MCP_VERSION:?PHASE8_MCP_VERSION is required}"
: "${PHASE8_A2A_VERSION:?PHASE8_A2A_VERSION is required}"
: "${PHASE8_TARGET_OS:?PHASE8_TARGET_OS is required}"
: "${PHASE8_TARGET_ARCH:?PHASE8_TARGET_ARCH is required}"
: "${PHASE8_BUNDLE_DIR:?PHASE8_BUNDLE_DIR is required}"
: "${PHASE8_SECURITY_DIR:?PHASE8_SECURITY_DIR is required}"
[[ -d "${PHASE8_BUNDLE_DIR}" && -d "${PHASE8_SECURITY_DIR}" ]] || { echo "Phase 8 bundle and security directories must exist." >&2; exit 2; }
[[ "$(find "${PHASE8_BUNDLE_DIR}" -maxdepth 1 -type f -name '*.murchalka' | wc -l | tr -d ' ')" -ge 8 ]] || { echo "Production bundles and all Phase 8 conformance fixtures are required." >&2; exit 2; }

repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_files=(-f "${repository}/compose/compose.phase8.yaml")
runtime_services=(phase8-runtime)
if [[ "$(uname -s)" == "Darwin" ]]; then
  : "${SOCAT_IMAGE:?SOCAT_IMAGE is required on macOS}"
  compose_files+=(-f "${repository}/compose/compose.phase8.macos.yaml")
  runtime_services+=(phase8-relay)
fi
compose=(docker compose --project-name murchalka-phase8-acceptance "${compose_files[@]}")
target="${PHASE8_TARGET_OS}-${PHASE8_TARGET_ARCH}"
unsigned_bundle="${PHASE8_BUNDLE_DIR}/phase8-unsigned-0.5.0-${target}.murchalka"
corrupt_bundle="${PHASE8_BUNDLE_DIR}/phase8-corrupt-0.5.0-${target}.murchalka"
tamper_directory="$(mktemp -d)"
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "${status}" -ne 0 ]]; then
    echo "Sanitized Root Audit tail:" >&2
    "${compose[@]}" exec -T phase8-runtime tail -n 100 /var/lib/murchalka/audit/root-audit.jsonl 2>/dev/null |
      jq -c '{Sequence,EventType,Subject,Outcome,ReasonCode}' >&2 || true
    "${compose[@]}" logs --no-color --tail 120 phase8-runtime 2>/dev/null || true
  fi
  "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -f -- "${unsigned_bundle}" "${corrupt_bundle}"
  rm -rf -- "${tamper_directory}"
  exit "${status}"
}
trap cleanup EXIT

cp "${PHASE8_BUNDLE_DIR}/phase8-unsigned-source-0.5.0-${target}.murchalka" "${unsigned_bundle}"
zip -q -d "${unsigned_bundle}" signature/signature.json
unzip -q "${PHASE8_BUNDLE_DIR}/phase8-corrupt-source-0.5.0-${target}.murchalka" -d "${tamper_directory}"
tampered_schema="${tamper_directory}/schemas/capabilities/conformance.echo.request.schema.json"
sed 's/"maximum": 30000/"maximum": 29999/' "${tampered_schema}" > "${tampered_schema}.tmp"
mv "${tampered_schema}.tmp" "${tampered_schema}"
cp "${PHASE8_BUNDLE_DIR}/phase8-corrupt-source-0.5.0-${target}.murchalka" "${corrupt_bundle}"
(cd "${tamper_directory}" && zip -X -q -u "${corrupt_bundle}" schemas/capabilities/conformance.echo.request.schema.json)

"${compose[@]}" up --detach "${runtime_services[@]}"
runtime=http://127.0.0.1:15078
gateway=http://127.0.0.1:5088
if [[ "$(uname -s)" == "Darwin" ]]; then gateway=http://127.0.0.1:15088; fi
for _ in {1..90}; do if curl --fail --silent "${runtime}/health" >/dev/null; then break; fi; sleep 1; done
curl --fail --silent "${runtime}/health" | jq -e --arg version "${PHASE8_RUNTIME_VERSION}" '.runtimeVersion == $version' >/dev/null
admin_token="$(tr -d '\r\n' < "${PHASE8_SECURITY_DIR}/admin-token")"
admin=(-H "Authorization: Bearer ${admin_token}")

module_status() {
  local module_id="$1"
  curl --fail --silent "${admin[@]}" "${runtime}/v1/modules" | jq -c --arg module_id "${module_id}" '.[] | select(.moduleId == $module_id)'
}
wait_module() {
  local module_id="$1" state="$2" version="${3:-}" current
  for _ in {1..90}; do
    current="$(module_status "${module_id}" || true)"
    if [[ -n "${current}" ]] && jq -e --argjson state "${state}" --arg version "${version}" '.state == $state and ($version == "" or .version == $version)' <<< "${current}" >/dev/null; then
      printf '%s' "${current}"
      return 0
    fi
    sleep 1
  done
  echo "Module ${module_id} did not reach state ${state}." >&2
  curl --fail --silent "${admin[@]}" "${runtime}/v1/modules" >&2 || true
  return 1
}
wait_bundle_rejection() {
  local reason_code="$1"
  for _ in {1..90}; do
    if "${compose[@]}" exec -T phase8-runtime cat /var/lib/murchalka/audit/root-audit.jsonl 2>/dev/null |
      jq -e --arg reason_code "${reason_code}" 'select(.EventType == "bundle.rejected" and .ReasonCode == $reason_code)' >/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "Bundle rejection '${reason_code}' was not audited." >&2
  return 1
}
hot_install() {
  local filename="$1"
  "${compose[@]}" exec -T phase8-runtime cp "/release-bundles/${filename}" /var/lib/murchalka/modules/inbox/
}
replace_configuration() {
  local module_id="$1" values="$2" revision
  revision="$(curl --fail --silent "${admin[@]}" "${runtime}/v1/modules/${module_id}/configuration" | jq -er '.revision')"
  curl --fail --silent --request PUT "${admin[@]}" --header 'Content-Type: application/json' --data "${values}" "${runtime}/v1/modules/${module_id}/configuration?expectedRevision=${revision}" >/dev/null
}

wait_module dev.murchalka.protocol-gateway 14 "${PHASE8_GATEWAY_VERSION}" >/dev/null
wait_module dev.murchalka.phase8-conformance 14 0.5.0 >/dev/null
curl --fail --silent "${gateway}/protocols" | jq -e '.routes == []' >/dev/null

gateway_values="$(jq -c '.values.allowAnonymousLoopback=true | .values' "${repository}/profiles/protocols/configuration/dev.murchalka.protocol-gateway.json")"
replace_configuration dev.murchalka.protocol-gateway "${gateway_values}"

hot_install "protocol-mcp-${PHASE8_MCP_VERSION}-${target}.murchalka"
wait_module dev.murchalka.protocol-mcp 14 "${PHASE8_MCP_VERSION}" >/dev/null
mcp_values="$(jq -c '.values.allowAnonymousLoopback=true | .values.tools=[{name:"conformance.echo",description:"Phase 8 bounded echo",capability:"conformance.echo",providerModule:"dev.murchalka.phase8-conformance",inputSchema:{type:"object",properties:{delayMilliseconds:{type:"integer",minimum:0,maximum:30000}}}}] | .values' "${repository}/profiles/protocols/configuration/dev.murchalka.protocol-mcp.json")"
replace_configuration dev.murchalka.protocol-mcp "${mcp_values}"
for _ in {1..60}; do
  routes="$(curl --fail --silent "${gateway}/protocols" || true)"
  if [[ -n "${routes}" ]] && jq -e '.routes == ["mcp"]' <<< "${routes}" >/dev/null; then break; fi
  sleep 1
done
jq -e '.routes == ["mcp"]' <<< "${routes}" >/dev/null

headers="$(mktemp)"
initialize='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"phase8","version":"1.0.0"}}}'
mcp_response="$(curl --fail --silent --dump-header "${headers}" --header 'Content-Type: application/json' --data "${initialize}" "${gateway}/protocols/mcp")"
jq -e '.result.protocolVersion == "2025-11-25" and .result.serverInfo.name == "Murchalka"' <<< "${mcp_response}" >/dev/null
session_id="$(awk 'tolower($1) == "mcp-session-id:" { gsub("\\r", "", $2); print $2 }' "${headers}")"
rm -f -- "${headers}"
[[ -n "${session_id}" ]]

tool_list='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
curl --fail --silent --header 'Content-Type: application/json' --header "Mcp-Session-Id: ${session_id}" --data "${tool_list}" "${gateway}/protocols/mcp" |
  jq -e '.result.tools | length == 1 and .[0].name == "conformance.echo"' >/dev/null
allowed='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"conformance.echo","arguments":{"delayMilliseconds":10,"value":"phase8"}}}'
curl --fail --silent --header 'Content-Type: application/json' --header "Mcp-Session-Id: ${session_id}" --data "${allowed}" "${gateway}/protocols/mcp" |
  jq -e '.result.isError == false and .result.structuredContent.ok == true and .result.structuredContent.capability == "conformance.echo"' >/dev/null
denied='{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"runtime.secrets","arguments":{}}}'
status="$(curl --silent --output /tmp/phase8-denied.json --write-out '%{http_code}' --header 'Content-Type: application/json' --header "Mcp-Session-Id: ${session_id}" --data "${denied}" "${gateway}/protocols/mcp")"
[[ "${status}" == 403 ]]
jq -e '.error.code == -32602' /tmp/phase8-denied.json >/dev/null

stream_request='{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"conformance.echo","arguments":{"delayMilliseconds":30000}}}'
stream_output="$(mktemp)"
curl --silent --max-time 5 --header 'Accept: text/event-stream' --header 'Content-Type: application/json' --header "Mcp-Session-Id: ${session_id}" --data "${stream_request}" "${gateway}/protocols/mcp" > "${stream_output}" || true
if ! grep -q 'event: progress' "${stream_output}"; then
  echo "MCP progress event was not observed. Bounded response follows:" >&2
  sed -n '1,20p' "${stream_output}" >&2
  exit 1
fi
rm -f -- "${stream_output}"

hot_install "protocol-a2a-${PHASE8_A2A_VERSION}-${target}.murchalka"
wait_module dev.murchalka.protocol-a2a 14 "${PHASE8_A2A_VERSION}" >/dev/null
a2a_values="$(jq -c '.values.allowAnonymousLoopback=true | .values.skills=[{id:"conformance",name:"Conformance",description:"Phase 8 bounded A2A skill",capability:"conformance.agent-turn",providerModule:"dev.murchalka.phase8-conformance",tags:["phase8"]}] | .values' "${repository}/profiles/protocols/configuration/dev.murchalka.protocol-a2a.json")"
replace_configuration dev.murchalka.protocol-a2a "${a2a_values}"
for _ in {1..60}; do
  routes="$(curl --fail --silent "${gateway}/protocols" || true)"
  if [[ -n "${routes}" ]] && jq -e '.routes | sort == ["a2a","mcp"]' <<< "${routes}" >/dev/null; then break; fi
  sleep 1
done
jq -e '.routes | sort == ["a2a","mcp"]' <<< "${routes}" >/dev/null

curl --fail --silent "${gateway}/protocols/a2a/.well-known/agent-card.json" |
  jq -e '.name == "Murchalka" and .capabilities.streaming == true and .capabilities.pushNotifications == true and (.skills | length == 1) and .skills[0].id == "conformance"' >/dev/null
a2a_message='{"skillId":"conformance","message":{"role":"user","parts":[{"kind":"text","text":"Phase 8"}]}}'
curl --fail --silent --header 'Content-Type: application/json' --data "${a2a_message}" "${gateway}/protocols/a2a/message:send" |
  jq -e '.status.state == "completed" and (.artifacts | length == 1) and .artifacts[0].parts[0].data.ok == true' >/dev/null
a2a_stream="$(mktemp)"
curl --silent --max-time 5 --header 'Accept: text/event-stream' --header 'Content-Type: application/json' --data "${a2a_message}" "${gateway}/protocols/a2a/message:stream" > "${a2a_stream}" || true
if ! grep -q 'event: task.status' "${a2a_stream}"; then
  echo "A2A task.status event was not observed. Bounded response follows:" >&2
  sed -n '1,20p' "${a2a_stream}" >&2
  exit 1
fi
rm -f -- "${a2a_stream}"

client_catalog="$(curl --fail --silent "${runtime}/client/v1/catalog")"
jq -e '.entries | length == 2 and ([.[].extensionId] | sort == ["protocol.a2a.agents","protocol.mcp.connections"]) and all(.[]; .targets == ["desktop","web"])' <<< "${client_catalog}" >/dev/null
curl --fail --silent --request POST "${admin[@]}" --header 'Content-Type: application/json' --data '{"payload":{"operation":"status"}}' "${runtime}/v1/capabilities/mcp.ui.action/invoke" |
  jq -e '.type == "mcp.status.completed" and (.tools | length == 1) and .tools[0].name == "conformance.echo"' >/dev/null
curl --fail --silent --request POST "${admin[@]}" --header 'Content-Type: application/json' --data '{"payload":{"operation":"status"}}' "${runtime}/v1/capabilities/a2a.ui.action/invoke" |
  jq -e '.type == "a2a.status.completed" and (.skills | length == 1) and (.tasks | length >= 2)' >/dev/null

for _ in {1..30}; do
  if "${compose[@]}" exec -T phase8-runtime grep -q '"EventType":"protocol.activity".*"Outcome":"denied"' /var/lib/murchalka/audit/root-audit.jsonl &&
     "${compose[@]}" exec -T phase8-runtime grep -q '"EventType":"protocol.activity".*"Outcome":"cancelled"' /var/lib/murchalka/audit/root-audit.jsonl; then break; fi
  sleep 1
done
"${compose[@]}" exec -T phase8-runtime grep -q '"EventType":"protocol.activity".*"Outcome":"denied"' /var/lib/murchalka/audit/root-audit.jsonl
"${compose[@]}" exec -T phase8-runtime grep -q '"EventType":"protocol.activity".*"Outcome":"cancelled"' /var/lib/murchalka/audit/root-audit.jsonl
if "${compose[@]}" exec -T phase8-runtime grep -Fq "${admin_token}" /var/lib/murchalka/audit/root-audit.jsonl; then echo "Administrative token leaked into Root audit." >&2; exit 1; fi

curl --fail --silent --request POST "${admin[@]}" "${runtime}/v1/modules/dev.murchalka.protocol-mcp/disable" >/dev/null
for _ in {1..30}; do routes="$(curl --fail --silent "${gateway}/protocols" || true)"; if [[ -n "${routes}" ]] && jq -e '.routes == ["a2a"]' <<< "${routes}" >/dev/null; then break; fi; sleep 1; done
jq -e '.routes == ["a2a"]' <<< "${routes}" >/dev/null
curl --fail --silent --request POST "${admin[@]}" "${runtime}/v1/modules/dev.murchalka.protocol-mcp/enable" >/dev/null
for _ in {1..60}; do routes="$(curl --fail --silent "${gateway}/protocols" || true)"; if [[ -n "${routes}" ]] && jq -e '.routes | sort == ["a2a","mcp"]' <<< "${routes}" >/dev/null; then break; fi; sleep 1; done
old_session_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --header 'Content-Type: application/json' --header "Mcp-Session-Id: ${session_id}" --data '{"jsonrpc":"2.0","id":6,"method":"ping","params":{}}' "${gateway}/protocols/mcp")"
[[ "${old_session_status}" != 200 ]]

hot_install "phase8-incompatible-0.5.0-${target}.murchalka"
hot_install "$(basename "${unsigned_bundle}")"
hot_install "$(basename "${corrupt_bundle}")"
wait_bundle_rejection runtime-incompatible
wait_bundle_rejection archive-invalid
wait_bundle_rejection file-hash-mismatch

candidate_bundle="phase8-conformance-0.5.1-${target}.murchalka"
candidate_digest="$(unzip -p "${PHASE8_BUNDLE_DIR}/${candidate_bundle}" manifest/module.lock.json | jq -er '.module.bundleDigest | sub("^sha256:"; "")')"
hot_install "${candidate_bundle}"
for _ in {1..90}; do
  if "${compose[@]}" exec -T phase8-runtime test -d "/var/lib/murchalka/modules/installed/sha256/${candidate_digest}"; then break; fi
  sleep 1
done
"${compose[@]}" exec -T phase8-runtime test -d "/var/lib/murchalka/modules/installed/sha256/${candidate_digest}"
for _ in {1..20}; do
  retained="$(module_status dev.murchalka.phase8-conformance)"
  jq -e '.state == 14 and .version == "0.5.0"' <<< "${retained}" >/dev/null
  sleep 1
done
curl --fail --silent --request POST "${admin[@]}" --header 'Content-Type: application/json' --data '{"payload":{"delayMilliseconds":10,"value":"post-rollback"}}' "${runtime}/v1/capabilities/conformance.echo/invoke" |
  jq -e '.ok == true and .capability == "conformance.echo"' >/dev/null

curl --fail --silent --request POST "${admin[@]}" "${runtime}/v1/modules/dev.murchalka.protocol-gateway/disable" >/dev/null
for _ in {1..30}; do if ! curl --silent --fail "${gateway}/health" >/dev/null; then break; fi; sleep 1; done
if curl --silent --fail "${gateway}/health" >/dev/null; then echo "Disabled Protocol Gateway remained reachable." >&2; exit 1; fi

echo "Phase 8 Protocol Modules acceptance passed."
