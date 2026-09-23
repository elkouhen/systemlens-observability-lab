#!/usr/bin/env bash
# Réconcilie les policies Fleet nécessaires aux quatre VM architecture.
set -euo pipefail

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:192.168.33.30}"
kibana_version="${KIBANA_VERSION:-9.4.3}"
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
  local current_policy

  # Ne jamais créer une policy Fleet via saved_objects : Kibana peut alors
  # l'afficher, mais Fleet ne lui attribue pas de revision et Fleet Server
  # reste bloqué en STARTING. Les anciennes versions du POC ont pu laisser
  # ce type d'objet derrière elles ; le migrer vers l'API Fleet native.
  current_policy="$(curl "${curl_args[@]}" \
    "${kibana_url}/api/fleet/agent_policies?perPage=1000")" || {
    printf 'Impossible de lire les policies Fleet avant la réconciliation de %s.\n' "${id}" >&2
    return 1
  }
  local policy_item
  policy_item="$(jq -c --arg id "${id}" '.items[] | select(.id == $id)' <<<"${current_policy}")"
  if jq -e '.revision | numbers' >/dev/null 2>&1 <<<"${policy_item}"; then
    curl "${curl_args[@]}" -X PUT "${kibana_url}/api/fleet/agent_policies/${id}" \
      --data "${payload}" >/dev/null
    return 0
  fi

  if [[ -n "${policy_item}" ]]; then
    curl "${curl_args[@]}" -X DELETE \
      "${kibana_url}/api/saved_objects/fleet-agent-policies/${id}" >/dev/null
  fi

  curl "${curl_args[@]}" -X POST "${kibana_url}/api/fleet/agent_policies" \
    --data "$(jq --arg id "${id}" '. + {id: $id}' <<<"${payload}")" >/dev/null
}

ensure_agent_policy eck-fleet-server \
  '{"name":"Fleet Server","namespace":"default","monitoring_enabled":["logs","metrics"],"is_default_fleet_server":true}'
ensure_agent_policy data-fleet \
  '{"name":"Data — Elastic Agent","namespace":"default","monitoring_enabled":["logs","metrics"],"is_default":true}'
ensure_agent_policy otel-fleet \
  '{"name":"OTel — Elastic Agent","namespace":"default","monitoring_enabled":["logs","metrics"]}'

install_package_from_registry() {
  local package_name="$1"
  local package_version="$2"
  local package_info install_status installed_version attempt

  # Les packages *_otel fournissent les dashboards et les assets Kibana pour
  # les métriques produites par les Collectors OTel. Les Collectors restent
  # autonomes et ne sont pas enrôlés comme agents Fleet.
  package_info="$(curl "${curl_args[@]}" \
    "${kibana_url}/api/fleet/epm/packages/${package_name}?withMetadata=true" 2>/dev/null || true)"
  install_status="$(jq -r '.item.install_status // .item.status // empty' <<<"${package_info}")"
  installed_version="$(jq -r '.item.version // empty' <<<"${package_info}")"
  if [[ "${install_status}" != 'installed' || "${installed_version}" != "${package_version}" ]]; then
    curl "${curl_args[@]}" -X POST \
      "${kibana_url}/api/fleet/epm/packages/${package_name}/${package_version}" \
      --data '{"ignore_constraints":false}' >/dev/null
  fi

  for attempt in $(seq 1 60); do
    package_info="$(curl "${curl_args[@]}" \
      "${kibana_url}/api/fleet/epm/packages/${package_name}?withMetadata=true")"
    install_status="$(jq -r '.item.install_status // .item.status // empty' <<<"${package_info}")"
    installed_version="$(jq -r '.item.version // empty' <<<"${package_info}")"
    case "${install_status}" in
      installed)
        [[ "${installed_version}" == "${package_version}" ]] || {
          printf 'Version inattendue pour %s : %s (attendu %s, Kibana %s)\n' \
            "${package_name}" "${installed_version:-inconnue}" "${package_version}" "${kibana_version}" >&2
          return 1
        }
        printf 'Intégration Fleet %s installée (version %s)\n' \
          "${package_name}" "${installed_version}"
        return 0
        ;;
      install_failed)
        printf 'Échec de l’installation de l’intégration Fleet %s : %s\n' \
          "${package_name}" "$(jq -r '.item.installationInfo.latest_install_failed_attempts[-1].error.message // "erreur inconnue"' <<<"${package_info}")" >&2
        return 1
        ;;
    esac
    sleep 2
  done

  printf 'Délai dépassé pour l’installation de l’intégration Fleet %s (état : %s)\n' \
    "${package_name}" "${install_status:-inconnu}" >&2
  return 1
}

install_package_from_registry kubernetes_otel "${KUBERNETES_OTEL_PACKAGE_VERSION:-2.6.0}"
install_package_from_registry kafka_otel "${KAFKA_OTEL_PACKAGE_VERSION:-0.3.1}"
install_package_from_registry postgresql_otel "${POSTGRESQL_OTEL_PACKAGE_VERSION:-0.5.0}"
install_package_from_registry mongodb_otel "${MONGODB_OTEL_PACKAGE_VERSION:-0.3.1}"
install_package_from_registry system_otel "${SYSTEM_OTEL_PACKAGE_VERSION:-0.3.0}"

# Un redémarrage ou une réinitialisation historique du Fleet Server peut
# laisser plusieurs enregistrements actifs pour le même hôte. L'architecture
# La plateforme n'en déploie qu'un seul : conserver celui qui a le dernier check-in et
# retirer uniquement les doublons de la policy Fleet Server.
fleet_server_agents="$(curl "${curl_args[@]}" \
  "${kibana_url}/api/fleet/agents?perPage=1000")"
duplicate_fleet_server_ids="$(jq -r '
  .items
  | map(select(.policy_id == "eck-fleet-server" and .active == true))
  | group_by(.local_metadata.host.hostname)[]
  | sort_by(.last_checkin // "")
  | reverse
  | .[1:]
  | .[].id
' <<<"${fleet_server_agents}")"
while IFS= read -r duplicate_id; do
  [[ -n "${duplicate_id}" ]] || continue
  curl "${curl_args[@]}" -X POST \
    "${kibana_url}/api/fleet/agents/${duplicate_id}/unenroll" >/dev/null
  curl "${curl_args[@]}" -X DELETE \
    "${kibana_url}/api/fleet/agents/${duplicate_id}" >/dev/null
  printf 'Ancien Fleet Server supprimé : %s\n' "${duplicate_id}"
done <<<"${duplicate_fleet_server_ids}"

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
put_policy system-otel-edge-01 "$(jq -n '{name:"system-otel-edge-01",namespace:"default",policy_id:"otel-fleet",condition:"host.name == '\''otel-edge-01'\''",package:{name:"system",version:"1.20.4"},inputs:{"system-system/metrics":{enabled:true}}}')"
put_policy system-elk-01 "$(jq -n '{name:"system-elk-01",namespace:"default",policy_id:"otel-fleet",condition:"host.name == '\''elk-01'\''",package:{name:"system",version:"1.20.4"},inputs:{"system-system/metrics":{enabled:true}}}')"
put_policy mongodb-poc-01 "$(jq -n '{name:"mongodb-poc-01",namespace:"default",policy_id:"data-fleet",condition:"${host.name} == '\''poc-01'\''",package:{name:"mongodb",version:"1.5.0"},inputs:{"mongodb-mongodb/metrics":{enabled:true,streams:{"mongodb.replstatus":{enabled:true}},vars:{hosts:["mongodb://127.0.0.1:27017"]}},"mongodb-logfile":{enabled:true,streams:{"mongodb.log":{enabled:true,vars:{paths:["/var/log/mongodb/mongod.log"]}}}}}}')"
put_policy kafka-poc-01 "$(jq -n '{name:"kafka-poc-01",namespace:"default",policy_id:"data-fleet",condition:"${host.name} == '\''poc-01'\''",package:{name:"kafka",version:"1.3.0"},inputs:{"kafka-kafka/metrics":{enabled:true,vars:{hosts:["127.0.0.1:9092"]}},"kafka-logfile":{enabled:true,streams:{"kafka.log":{enabled:true,vars:{kafka_home:"/var/log/kafka",paths:["/controller.log*","/server.log*","/state-change.log*","/kafka-*.log*"]}}}}}}')"
put_policy postgresql-poc-01 "$(jq -n --arg password "${POSTGRESQL_PASSWORD}" '{name:"postgresql-poc-01",namespace:"default",policy_id:"data-fleet",condition:"${host.name} == '\''poc-01'\''",package:{name:"postgresql",version:"1.5.0"},inputs:{"postgresql-postgresql/metrics":{enabled:true,streams:{"postgresql.statement":{enabled:true}},vars:{hosts:["postgres://127.0.0.1:5432/observability_test?sslmode=disable"],username:"observability",password:$password}},"postgresql-logfile":{enabled:true,streams:{"postgresql.log":{enabled:true,vars:{paths:["/var/log/postgresql/postgresql.log"]}}}}}}')"

printf 'Policies Fleet réconciliées\n'
