#!/usr/bin/env bash
# Corrige les libellés hérités du schéma PostgreSQL classique dans Lens.
set -euo pipefail

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:192.168.33.30}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant la réconciliation}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/postgresql-otel-dashboard-ids.sh"
source "${script_dir}/dashboard-reconciliation-audit.sh"
load_postgresql_otel_dashboard_ids

markdown='## [PostgreSQL OTel] Dashboard

This dashboard exposes the PostgreSQL OTel receiver signals actually collected:
- Connection capacity and utilization
- Commit and rollback rates
- Database size and bgwriter activity

Query-level statistics, locks and pg_stat_statements are not exposed by this receiver.'

for dashboard_id in "${dashboard_ids[@]}"; do
  dashboard_json="$(curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}")"
  dashboard_json="$(printf '%s' "${dashboard_json}" | jq -ce --arg markdown "${markdown}" \
    '
    .attributes.panelsJSON |= (fromjson | walk(
      if type == "object" and has("fieldName") and .fieldName == "deadlocks" then .label = "Rollbacks/sec"
      elif type == "object" and has("fieldName") and .fieldName == "temp_files" then .label = "Database Size"
      elif type == "object" and has("fieldName") and .fieldName == "hit_ratio" then .label = "Commit Ratio"
      elif type == "object" and has("markdown") and (.markdown | type) == "string" then
        .markdown = $markdown
      elif type == "object" and has("params") and (.params.markdown? != null) then
        .params.markdown = $markdown
      else . end
    ) | tojson)'
    )"

  attributes="$(jq -ce '.attributes' <<<"${dashboard_json}")"
  curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -H 'kbn-xsrf: systemlens-otel-dashboard-labels' \
    -X PUT "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}" \
    --data "$(jq -cn --argjson attributes "${attributes}" '{attributes:$attributes}')" \
    >/dev/null
  record_dashboard_reconciliation "${dashboard_id}" "libellés et description PostgreSQL OTel"

  printf 'Libellés PostgreSQL OTel réconciliés : %s\n' "${dashboard_id}"
done
