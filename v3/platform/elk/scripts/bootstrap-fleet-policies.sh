#!/usr/bin/env bash
# Réconcilie les policies Fleet nécessaires aux quatre VM v3.
set -euo pipefail

kibana_url="${KIBANA_URL:-https://kibana.observability.test}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:443:127.0.0.1}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de configurer Fleet}"
: "${POSTGRESQL_PASSWORD:?Définir POSTGRESQL_PASSWORD avant de configurer Fleet}"

curl_args=(--fail --silent --show-error --insecure --resolve "${kibana_resolve}"
  -u "elastic:${KIBANA_PASSWORD}" -H 'kbn-xsrf: systemlens-fleet-bootstrap'
  -H 'Content-Type: application/json')

put_policy() {
  local id="$1" payload="$2"
  local existing_id
  local http_code
  existing_id="$(curl "${curl_args[@]}" "${kibana_url}/api/fleet/package_policies?perPage=1000" |
    jq -r --arg name "$(jq -r '.name' <<<"${payload}")" '.items[] | select(.name == $name) | .id' | head -n 1)"
  if [[ -n "${existing_id}" && "${existing_id}" != "null" ]]; then
    http_code="$(curl "${curl_args[@]}" -X PUT "${kibana_url}/api/fleet/package_policies/${existing_id}" \
      --data "${payload}" -o /dev/null -w '%{http_code}' || true)"
    [[ "${http_code}" == 2* ]] && return 0
    printf 'Échec de mise à jour Fleet %s (HTTP %s)\n' "${id}" "${http_code}" >&2
    return 1
  fi
  http_code="$(curl "${curl_args[@]}" -X POST "${kibana_url}/api/fleet/package_policies" \
    --data "${payload}" -o /dev/null -w '%{http_code}' || true)"
  [[ "${http_code}" == 2* ]] && return 0
  printf 'Échec de création Fleet %s (HTTP %s)\n' "${id}" "${http_code}" >&2
  return 1
}

ensure_agent_policy() {
  local id="$1" payload="$2"
  if ! curl "${curl_args[@]}" -X PUT "${kibana_url}/api/fleet/agent_policies/${id}" \
    --data "${payload}" >/dev/null 2>&1; then
    curl "${curl_args[@]}" -X POST "${kibana_url}/api/saved_objects/fleet-agent-policies/${id}" \
      --data "$(jq -n --argjson attributes "${payload}" '{attributes: $attributes}')" >/dev/null
  fi
}

ensure_agent_policy eck-fleet-server \
  '{"name":"Fleet Server","namespace":"default","monitoring_enabled":["logs","metrics"],"is_default_fleet_server":true}'
ensure_agent_policy data-fleet \
  '{"name":"Data — Elastic Agent","namespace":"default","monitoring_enabled":["logs","metrics"],"is_default":true}'
ensure_agent_policy otel-fleet \
  '{"name":"OTel — Elastic Agent","namespace":"default","monitoring_enabled":["logs","metrics"]}'

# Fleet Server reste en attente tant que sa policy ne possède pas au moins une
# clé d'enrôlement active. Créer cette clé une seule fois permet au Quadlet de
# démarrer correctement après une réinstallation ou une nouvelle VM.
fleet_server_enrollment_keys="$(curl "${curl_args[@]}" \
  "${kibana_url}/api/fleet/enrollment_api_keys?perPage=1000" |
  jq '[.items[] | select(.policy_id == "eck-fleet-server" and .active == true)] | length')"
if [[ "${fleet_server_enrollment_keys}" == '0' ]]; then
  curl "${curl_args[@]}" -X POST "${kibana_url}/api/fleet/enrollment_api_keys" \
    --data '{"name":"systemlens-fleet-server-bootstrap","policy_id":"eck-fleet-server"}' >/dev/null
fi

put_policy fleet-server-1 "$(jq -n '{name:"fleet_server-1",namespace:"default",policy_id:"eck-fleet-server",package:{name:"fleet_server",version:"1.2.0"},inputs:{"fleet_server-fleet-server":{enabled:true}}}')"
put_policy system-poc-01 "$(jq -n '{name:"system-poc-01",namespace:"default",policy_id:"data-fleet",condition:"host.name == '\''poc-01'\''",package:{name:"system",version:"1.20.4"},inputs:{"system-system/metrics":{enabled:true}}}')"
put_policy system-otel-backend-01 "$(jq -n '{name:"system-otel-backend-01",namespace:"default",policy_id:"otel-fleet",condition:"host.name == '\''otel-backend-01'\''",package:{name:"system",version:"1.20.4"},inputs:{"system-system/metrics":{enabled:true}}}')"
put_policy system-edge-01 "$(jq -n '{name:"system-edge-01",namespace:"default",policy_id:"otel-fleet",condition:"host.name == '\''edge-01'\''",package:{name:"system",version:"1.20.4"},inputs:{"system-system/metrics":{enabled:true}}}')"
put_policy system-elk-01 "$(jq -n '{name:"system-elk-01",namespace:"default",policy_id:"otel-fleet",condition:"host.name == '\''elk-01'\''",package:{name:"system",version:"1.20.4"},inputs:{"system-system/metrics":{enabled:true}}}')"
put_policy mongodb-poc-01 "$(jq -n '{name:"mongodb-poc-01",namespace:"default",policy_id:"data-fleet",condition:"host.name == '\''poc-01'\''",package:{name:"mongodb",version:"1.5.0"},inputs:{"mongodb-mongodb/metrics":{enabled:true,streams:{"mongodb.replstatus":{enabled:false}},vars:{hosts:["mongodb://127.0.0.1:27017"]}}}}')"
put_policy kafka-poc-01 "$(jq -n '{name:"kafka-poc-01",namespace:"default",policy_id:"data-fleet",condition:"host.name == '\''poc-01'\''",package:{name:"kafka",version:"1.3.0"},inputs:{"kafka-kafka/metrics":{enabled:true,vars:{hosts:["127.0.0.1:9092"]}}}}')"
put_policy postgresql-poc-01 "$(jq -n --arg password "${POSTGRESQL_PASSWORD}" '{name:"postgresql-poc-01",namespace:"default",policy_id:"data-fleet",condition:"host.name == '\''poc-01'\''",package:{name:"postgresql",version:"1.5.0"},inputs:{"postgresql-postgresql/metrics":{enabled:true,streams:{"postgresql.statement":{enabled:false}},vars:{hosts:["postgres://127.0.0.1:5432/observability_test?sslmode=disable"],username:"observability",password:$password}}}}')"

printf 'Policies Fleet v3 réconciliées\n'
