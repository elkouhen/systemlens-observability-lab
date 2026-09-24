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
install_package_from_registry otel_collector_internal_telemetry "${OTEL_COLLECTOR_INTERNAL_TELEMETRY_PACKAGE_VERSION:-1.2.3}"

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

postgresql_policy_id="$(curl "${curl_args[@]}" "${kibana_url}/api/fleet/package_policies?perPage=1000" |
  jq -r '.items[] | select(.name == "postgresql-poc-01") | .id' | head -n 1)"
[[ -n "${postgresql_policy_id}" && "${postgresql_policy_id}" != "null" ]] || {
  printf 'La package policy PostgreSQL préconfigurée est introuvable.\n' >&2
  exit 1
}
postgresql_policy="$(curl "${curl_args[@]}" "${kibana_url}/api/fleet/package_policies/${postgresql_policy_id}")"
postgresql_policy="$(jq --arg password "${POSTGRESQL_PASSWORD}" \
  'del(.id, .revision, .created_at, .updated_at, .created_by, .updated_by)
   | .inputs["postgresql-postgresql/metrics"].vars.password = $password' <<<"${postgresql_policy}")"
curl "${curl_args[@]}" -X PUT "${kibana_url}/api/fleet/package_policies/${postgresql_policy_id}" \
  --data "${postgresql_policy}" >/dev/null

printf 'Policies Fleet réconciliées\n'
