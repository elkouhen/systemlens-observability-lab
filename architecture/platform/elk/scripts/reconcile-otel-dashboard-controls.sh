#!/usr/bin/env bash
# Réconcilie les filtres des dashboards OTel avec les attributs réellement indexés.
set -euo pipefail

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:192.168.33.30}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant la réconciliation}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/postgresql-otel-dashboard-ids.sh"
source "${script_dir}/dashboard-reconciliation-audit.sh"

host_control='{"otel-host-filter":{"explicitInput":{"dataViewId":"metrics-*","fieldName":"resource.attributes.host.name","id":"otel-host-filter","searchTechnique":"prefix","selectedOptions":[],"sort":{"by":"_count","direction":"desc"},"title":"Hôte"},"grow":false,"order":0,"type":"optionsListControl","width":"medium"}}'
mongo_server_control='{"otel-mongo-server-filter":{"explicitInput":{"dataViewId":"metrics-*","fieldName":"resource.attributes.server.address","id":"otel-mongo-server-filter","searchTechnique":"prefix","selectedOptions":[],"sort":{"by":"_count","direction":"desc"},"title":"Serveur MongoDB"},"grow":false,"order":0,"type":"optionsListControl","width":"medium"}}'

load_postgresql_otel_dashboard_ids

for dashboard_id in "${dashboard_ids[@]}"; do
  dashboard_json="$(curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}")"
  attributes="$(jq -c --arg panels "${host_control}" \
    '.attributes
     | .controlGroupInput.panelsJSON = $panels
     | .controlGroupInput.controlStyle = "oneLine"
     | .timeFrom = "now-15m"
     | .timeTo = "now"
     | .timeRestore = true' \
    <<<"${dashboard_json}")"
  curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -H 'kbn-xsrf: systemlens-otel-dashboard-controls' \
    -X PUT "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}" \
    --data "$(jq -cn --argjson attributes "${attributes}" '{attributes:$attributes}')" \
    >/dev/null
  record_dashboard_reconciliation "${dashboard_id}" "contrôles OTel PostgreSQL"
  printf 'Dashboard OTel réconcilié : %s\n' "${dashboard_id}"
done

mongo_dashboard_ids=(
  mongodb_otel-overview
  mongodb_otel-capacity
  mongodb_otel-operations
)

for dashboard_id in "${mongo_dashboard_ids[@]}"; do
  dashboard_json="$(curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}")"
  attributes="$(jq -c --arg panels "${mongo_server_control}" \
    '.attributes
     | .controlGroupInput.panelsJSON = $panels
     | .controlGroupInput.controlStyle = "oneLine"
     | .timeFrom = "now-15m"
     | .timeTo = "now"
     | .timeRestore = true' \
    <<<"${dashboard_json}")"
  curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -H 'kbn-xsrf: systemlens-mongodb-dashboard-controls' \
    -X PUT "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}" \
    --data "$(jq -cn --argjson attributes "${attributes}" '{attributes:$attributes}')" \
    >/dev/null
  record_dashboard_reconciliation "${dashboard_id}" "contrôle Serveur MongoDB OTel"
  printf 'Dashboard MongoDB OTel réconcilié : %s\n' "${dashboard_id}"
done
