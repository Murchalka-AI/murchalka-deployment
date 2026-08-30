#!/usr/bin/env bash
set -euo pipefail

for tool in curl docker jq unzip zip; do command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 2; }; done
: "${MURCHALKA_RUNTIME_IMAGE:?MURCHALKA_RUNTIME_IMAGE is required}"
: "${PHASE8_BUNDLE_DIR:?PHASE8_BUNDLE_DIR is required}"
: "${PHASE8_SECURITY_DIR:?PHASE8_SECURITY_DIR is required}"
[[ -d "${PHASE8_BUNDLE_DIR}" && -d "${PHASE8_SECURITY_DIR}" ]] || { echo "Phase 8 bundle and security directories must exist." >&2; exit 2; }
[[ "$(find "${PHASE8_BUNDLE_DIR}" -maxdepth 1 -type f -name '*.murchalka' | wc -l | tr -d ' ')" -ge 8 ]] || { echo "Production bundles and all Phase 8 conformance fixtures are required." >&2; exit 2; }

repository="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose=(docker compose --project-name murchalka-phase8-acceptance -f "${repository}/compose/compose.phase8.yaml")
unsigned_bundle="${PHASE8_BUNDLE_DIR}/phase8-unsigned-0.5.0-linux-x64.murchalka"
corrupt_bundle="${PHASE8_BUNDLE_DIR}/phase8-corrupt-0.5.0-linux-x64.murchalka"
tamper_directory="$(mktemp -d)"
cleanup() {
  "${compose[@]}" logs --no-color phase8-runtime 2>/dev/null || true
  "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -f -- "${unsigned_bundle}" "${corrupt_bundle}"
  rm -rf -- "${tamper_directory}"
}
trap cleanup EXIT

cp "${PHASE8_BUNDLE_DIR}/phase8-unsigned-source-0.5.0-linux-x64.murchalka" "${unsigned_bundle}"
zip -q -d "${unsigned_bundle}" signature/signature.json
unzip -q "${PHASE8_BUNDLE_DIR}/phase8-corrupt-source-0.5.0-linux-x64.murchalka" -d "${tamper_directory}"
sed -i 's/"maximum": 30000/"maximum": 29999/' "${tamper_directory}/schemas/capabilities/conformance.echo.request.schema.json"
(cd "${tamper_directory}" && zip -X -q -r "${corrupt_bundle}" .)

"${compose[@]}" up --detach phase8-runtime
runtime=http://127.0.0.1:15078
gateway=http://127.0.0.1:5088
for _ in {1..90}; do if curl --fail --silent "${runtime}/health" >/dev/null; then break; fi; sleep 1; done
curl --fail --silent "${runtime}/health" | jq -e '.runtimeVersion == "0.5.0"' >/dev/null
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
hot_install() {
  local filename="$1"
  "${compose[@]}" exec -T phase8-runtime cp "/release-bundles/${filename}" /var/lib/murchalka/modules/inbox/
}
replace_configuration() {
  local module_id="$1" values="$2" revision
  revision="$(curl --fail --silent "${admin[@]}" "${runtime}/v1/modules/${module_id}/configuration" | jq -er '.revision')"
  curl --fail --silent --request PUT "${admin[@]}" --header 'Content-Type: application/json' --data "${values}" "${runtime}/v1/modules/${module_id}/configuration?expectedRevision=${revision}" >/dev/null
}

wait_module dev.murchalka.protocol-gateway 14 0.5.0 >/dev/null
wait_module dev.murchalka.phase8-conformance 14 0.5.0 >/dev/null
curl --fail --silent "${gateway}/protocols" | jq -e '.routes == []' >/dev/null

gateway_values="$(jq -c '.values.allowAnonymousLoopback=true | .values' "${repository}/configuration/dev.murchalka.protocol-gateway.json")"
replace_configuration dev.murchalka.protocol-gateway "${gateway_values}"

hot_install protocol-mcp-0.5.0-linux-x64.murchalka
wait_module dev.murchalka.protocol-mcp 14 0.5.0 >/dev/null
mcp_values="$(jq -c '.values.allowAnonymousLoopback=true | .values.tools=[{name:"conformance.echo",description:"Phase 8 bounded echo",capability:"conformance.echo",providerModule:"dev.murchalka.phase8-conformance",inputSchema:{type:"object",properties:{delayMilliseconds:{type:"integer",minimum:0,maximum:30000}}}}] | .values' "${repository}/configuration/dev.murchalka.protocol-mcp.json")"
replace_configuration dev.murchalka.protocol-mcp "${mcp_values}"
for _ in {1..60}; do
  routes="$(curl --fail --silent "${gateway}/protocols")"
  if jq -e '.routes == ["mcp"]' <<< "${routes}" >/dev/null; then break; fi
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
curl --silent --max-time 1 --header 'Accept: text/event-stream' --header 'Content-Type: application/json' --header "Mcp-Session-Id: ${session_id}" --data "${stream_request}" "${gateway}/protocols/mcp" > "${stream_output}" || true
grep -q 'event: progress' "${stream_output}"
rm -f -- "${stream_output}"

hot_install protocol-a2a-0.5.0-linux-x64.murchalka
wait_module dev.murchalka.protocol-a2a 14 0.5.0 >/dev/null
a2a_values="$(jq -c '.values.allowAnonymousLoopback=true | .values.skills=[{id:"conformance",name:"Conformance",description:"Phase 8 bounded A2A skill",capability:"conformance.agent-turn",providerModule:"dev.murchalka.phase8-conformance",tags:["phase8"]}] | .values' "${repository}/configuration/dev.murchalka.protocol-a2a.json")"
replace_configuration dev.murchalka.protocol-a2a "${a2a_values}"
for _ in {1..60}; do
  routes="$(curl --fail --silent "${gateway}/protocols")"
  if jq -e '.routes | sort == ["a2a","mcp"]' <<< "${routes}" >/dev/null; then break; fi
  sleep 1
done
jq -e '.routes | sort == ["a2a","mcp"]' <<< "${routes}" >/dev/null

curl --fail --silent "${gateway}/protocols/a2a/.well-known/agent-card.json" |
  jq -e '.name == "Murchalka" and .capabilities.streaming == true and .capabilities.pushNotifications == true and (.skills | length == 1) and .skills[0].id == "conformance"' >/dev/null
a2a_message='{"skillId":"conformance","message":{"role":"user","parts":[{"kind":"text","text":"Phase 8"}]}}'
curl --fail --silent --header 'Content-Type: application/json' --data "${a2a_message}" "${gateway}/protocols/a2a/message:send" |
  jq -e '.status.state == "completed" and (.artifacts | length == 1) and .artifacts[0].parts[0].data.ok == true' >/dev/null
a2a_stream="$(mktemp)"
curl --silent --max-time 1 --header 'Accept: text/event-stream' --header 'Content-Type: application/json' --data "${a2a_message}" "${gateway}/protocols/a2a/message:stream" > "${a2a_stream}" || true
grep -q 'event: status' "${a2a_stream}"
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
for _ in {1..30}; do routes="$(curl --fail --silent "${gateway}/protocols")"; if jq -e '.routes == ["a2a"]' <<< "${routes}" >/dev/null; then break; fi; sleep 1; done
jq -e '.routes == ["a2a"]' <<< "${routes}" >/dev/null
curl --fail --silent --request POST "${admin[@]}" "${runtime}/v1/modules/dev.murchalka.protocol-mcp/enable" >/dev/null
for _ in {1..60}; do routes="$(curl --fail --silent "${gateway}/protocols")"; if jq -e '.routes | sort == ["a2a","mcp"]' <<< "${routes}" >/dev/null; then break; fi; sleep 1; done
old_session_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --header 'Content-Type: application/json' --header "Mcp-Session-Id: ${session_id}" --data '{"jsonrpc":"2.0","id":6,"method":"ping","params":{}}' "${gateway}/protocols/mcp")"
[[ "${old_session_status}" != 200 ]]

hot_install phase8-incompatible-0.5.0-linux-x64.murchalka
hot_install "$(basename "${unsigned_bundle}")"
hot_install "$(basename "${corrupt_bundle}")"
wait_module dev.murchalka.phase8-incompatible 8 >/dev/null
wait_module dev.murchalka.phase8-unsigned 19 >/dev/null
wait_module dev.murchalka.phase8-corrupt 19 >/dev/null

prior_revision="$(module_status dev.murchalka.phase8-conformance | jq -er '.revision')"
hot_install phase8-conformance-0.5.1-linux-x64.murchalka
for _ in {1..90}; do
  rollback="$(module_status dev.murchalka.phase8-conformance || true)"
  if jq -e --argjson prior "${prior_revision}" '.revision > $prior and .state == 14 and .version == "0.5.0"' <<< "${rollback}" >/dev/null; then break; fi
  sleep 1
done
jq -e --argjson prior "${prior_revision}" '.revision > $prior and .state == 14 and .version == "0.5.0"' <<< "${rollback}" >/dev/null

curl --fail --silent --request POST "${admin[@]}" "${runtime}/v1/modules/dev.murchalka.protocol-gateway/disable" >/dev/null
for _ in {1..30}; do if ! curl --silent --fail "${gateway}/health" >/dev/null; then break; fi; sleep 1; done
if curl --silent --fail "${gateway}/health" >/dev/null; then echo "Disabled Protocol Gateway remained reachable." >&2; exit 1; fi

echo "Phase 8 Protocol Modules acceptance passed."

