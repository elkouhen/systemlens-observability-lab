#!/usr/bin/env bash
# Corrige les panneaux PostgreSQL OTel qui ciblaient le schéma d’intégration classique.
set -euo pipefail

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:192.168.33.30}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant la réconciliation}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/postgresql-otel-dashboard-ids.sh"
source "${script_dir}/dashboard-reconciliation-audit.sh"

elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
elasticsearch_user="${ELASTICSEARCH_USERNAME:-elastic}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:192.168.33.40}"
elasticsearch_password="${ELASTICSEARCH_PASSWORD:-${KIBANA_PASSWORD}}"
end_time="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
  start_time="$(date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ')"
else
  start_time="$(date -u -d '15 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')"
fi

load_postgresql_otel_dashboard_ids

patch_panel() {
  local old_title="$1"
  local new_title="$2"
  local query="$3"
  local target_title
  if jq -e --arg old_title "${old_title}" \
    '.attributes.panelsJSON | fromjson | any(.[]; .embeddableConfig.attributes.title == $old_title)' \
    <<<"${dashboard_json}" >/dev/null; then
    target_title="${old_title}"
  elif jq -e --arg new_title "${new_title}" \
    '.attributes.panelsJSON | fromjson | any(.[]; .embeddableConfig.attributes.title == $new_title)' \
    <<<"${dashboard_json}" >/dev/null; then
    target_title="${new_title}"
  else
    return 0
  fi
  dashboard_json="$(jq -c \
    --arg target_title "${target_title}" \
    --arg new_title "${new_title}" \
    --arg query "${query}" \
    '.attributes.panelsJSON = (.attributes.panelsJSON | fromjson |
      map(if .embeddableConfig.attributes.title == $target_title then
        .embeddableConfig.attributes.title = $new_title
        | .embeddableConfig.attributes.state.query.esql = $query
        | (.embeddableConfig.attributes.state.datasourceStates.textBased.layers // {})
          |= with_entries(.value.query.esql = $query)
      else . end) | tojson)' \
    <<<"${dashboard_json}")"

  normalized_query="$(printf '%s' "${query}" | sed "s/?_tstart/TO_DATETIME(\"${start_time}\")/g; s/?_tend/TO_DATETIME(\"${end_time}\")/g")"
  query_response="$(curl --fail --silent --show-error --insecure \
    --resolve "${elasticsearch_resolve}" \
    -u "${elasticsearch_user}:${elasticsearch_password}" \
    -H 'Content-Type: application/json' \
    -X POST "${elasticsearch_url}/_query" \
    --data "$(jq -cn --arg query "${normalized_query}" '{query:$query}')")"
  if jq -e '.error != null' <<<"${query_response}" >/dev/null; then
    printf 'Requête ES|QL invalide pour le panneau %s : %s\n' "${new_title}" \
      "$(jq -r '.error.reason // .error.type // "erreur inconnue"' <<<"${query_response}" | tr '\n' ' ')" >&2
    return 1
  fi
  columns="$(jq -c '[.columns[]?.name]' <<<"${query_response}")"
  dashboard_json="$(jq -c --arg title "${new_title}" --argjson fields "${columns}" \
    '.attributes.panelsJSON = (.attributes.panelsJSON | fromjson |
      map(if .embeddableConfig.attributes.title == $title then
        .embeddableConfig.attributes.state.visualization.columns =
          ((.embeddableConfig.attributes.state.visualization.columns // [])[:($fields | length)])
        | .embeddableConfig.attributes.state.datasourceStates.textBased.layers |= with_entries(
            .value |= (. as $layer
              | .columns = [range(0; ($fields | length)) as $i
                  | (($layer.columns[$i] // {}) + {fieldName:$fields[$i], columnId:($layer.columns[$i].columnId // ("esql-column-" + ($i|tostring)))})]
              | .allColumns = .columns)
          )
      else . end) | tojson)' \
    <<<"${dashboard_json}")"
}

repair_panel_visualization() {
  local title="$1"
  local kind="$2"
  dashboard_json="$(jq -c --arg title "${title}" --arg kind "${kind}" '
    .attributes.panelsJSON = (.attributes.panelsJSON | fromjson |
      map(if .embeddableConfig.attributes.title == $title then
        (.embeddableConfig.attributes.state.datasourceStates.textBased.layers | to_entries[0].value.columns) as $columns
        | ($columns | map({key:.fieldName, value:.columnId}) | from_entries) as $ids
        | .embeddableConfig.attributes.state.datasourceStates.textBased.layers |= with_entries(
            .value.columns |= map(
              if .fieldName == "deadlocks" then .label = "Rollbacks/sec" | .customLabel = true | .meta = {type:"number", esType:"double"}
              elif .fieldName == "database_count" then .label = "Database count" | .customLabel = true | .meta = {type:"number", esType:"long"}
              elif .fieldName == "table_count" then .label = "Table count" | .customLabel = true | .meta = {type:"number", esType:"long"}
              elif .fieldName == "resource.attributes.postgresql.database.name" then .label = "Database" | .customLabel = true | .meta = {type:"string", esType:"keyword"}
              elif .fieldName == "time_bucket" then .label = "Time" | .customLabel = true | .meta = {type:"date", esType:"date"}
              elif .fieldName == "utilization" then .label = "Connection utilization" | .customLabel = true | .meta = {type:"number", esType:"double"}
              elif .fieldName == "min_val" then .label = "Minimum" | .customLabel = true | .meta = {type:"number", esType:"double"}
              elif .fieldName == "max_val" then .label = "Maximum" | .customLabel = true | .meta = {type:"number", esType:"double"}
              else . end)
          )
        | if $kind == "time" then
            .embeddableConfig.attributes.state.visualization.layers[0].accessors = [$ids["deadlocks"] // $ids["database_count"]]
            | .embeddableConfig.attributes.state.visualization.layers[0].xAccessor = $ids.time_bucket
            | del(.embeddableConfig.attributes.state.visualization.layers[0].splitAccessor)
          elif $kind == "database" then
            .embeddableConfig.attributes.state.visualization.layers[0].accessors = [$ids.database_count, $ids.table_count]
            | .embeddableConfig.attributes.state.visualization.layers[0].xAccessor = $ids["resource.attributes.postgresql.database.name"]
            | del(.embeddableConfig.attributes.state.visualization.layers[0].splitAccessor)
            | .embeddableConfig.attributes.state.visualization.layers[0].seriesType = "bar"
          elif $kind == "gauge" then
            .embeddableConfig.attributes.state.visualization.metricAccessor = $ids.utilization
            | .embeddableConfig.attributes.state.visualization.minAccessor = $ids.min_val
            | .embeddableConfig.attributes.state.visualization.maxAccessor = $ids.max_val
            | del(.embeddableConfig.attributes.state.visualization.goalAccessor)
          else . end
      else . end) | tojson)' <<<"${dashboard_json}")"
}

for dashboard_id in "${dashboard_ids[@]}"; do
  dashboard_json="$(curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}")"

  patch_panel 'Deadlocks' 'Rollback Rate' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.rollbacks IS NOT NULL\n| STATS deadlocks = SUM(RATE(postgresql.rollbacks))'
  patch_panel 'Temp Files' 'Database Size' $'FROM metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.db_size IS NOT NULL\n| STATS temp_files = MAX(postgresql.db_size)'
  patch_panel 'Buffer Hit Ratio' 'Commit / Rollback Ratio' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.commits IS NOT NULL OR postgresql.rollbacks IS NOT NULL\n| STATS commits = SUM(RATE(postgresql.commits)), rollbacks = SUM(RATE(postgresql.rollbacks))\n| EVAL hit_ratio = CASE(commits + rollbacks > 0, TO_DOUBLE(commits) / TO_DOUBLE(commits + rollbacks), 0)'
  patch_panel 'Commit / Rollback Mix' 'Commit / Rollback Ratio' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.commits IS NOT NULL OR postgresql.rollbacks IS NOT NULL\n| STATS commits = SUM(RATE(postgresql.commits)), rollbacks = SUM(RATE(postgresql.rollbacks))\n| EVAL hit_ratio = CASE(commits + rollbacks > 0, TO_DOUBLE(commits) / TO_DOUBLE(commits + rollbacks), 0)'
  patch_panel 'Database Health Summary' 'Database Health Summary' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.backends IS NOT NULL OR postgresql.db_size IS NOT NULL OR postgresql.commits IS NOT NULL OR postgresql.rollbacks IS NOT NULL\n| STATS connections = SUM(LAST_OVER_TIME(postgresql.backends)), commits = SUM(RATE(postgresql.commits)), rollbacks = SUM(RATE(postgresql.rollbacks)), db_size = MAX(postgresql.db_size) BY resource.attributes.postgresql.database.name\n| EVAL rollback_pct = CASE(commits + rollbacks > 0, TO_DOUBLE(rollbacks) / TO_DOUBLE(commits + rollbacks), 0), deadlocks = rollbacks, hit_ratio = CASE(commits + rollbacks > 0, TO_DOUBLE(commits) / TO_DOUBLE(commits + rollbacks), 0), temp_files = db_size'
  patch_panel 'Buffer Hit Ratio Over Time' 'Commit / Rollback Ratio Over Time' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.commits IS NOT NULL OR postgresql.rollbacks IS NOT NULL\n| STATS commits = SUM(RATE(postgresql.commits)), rollbacks = SUM(RATE(postgresql.rollbacks)) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend), resource.attributes.postgresql.database.name\n| EVAL hit_ratio = CASE(commits + rollbacks > 0, TO_DOUBLE(commits) / TO_DOUBLE(commits + rollbacks), 0)\n| SORT time_bucket ASC'
  patch_panel 'Commit / Rollback Mix Over Time' 'Commit / Rollback Ratio Over Time' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.commits IS NOT NULL OR postgresql.rollbacks IS NOT NULL\n| STATS commits = SUM(RATE(postgresql.commits)), rollbacks = SUM(RATE(postgresql.rollbacks)) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend), resource.attributes.postgresql.database.name\n| EVAL hit_ratio = CASE(commits + rollbacks > 0, TO_DOUBLE(commits) / TO_DOUBLE(commits + rollbacks), 0)\n| SORT time_bucket ASC'
  patch_panel 'Deadlocks Over Time' 'Rollback Rate Over Time' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.rollbacks IS NOT NULL\n| STATS deadlocks = SUM(RATE(postgresql.rollbacks)) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend)\n| SORT time_bucket ASC'
  patch_panel 'Temp Files and I/O Over Time' 'Database Size and Buffer Writes Over Time' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.db_size IS NOT NULL OR postgresql.bgwriter.buffers.writes IS NOT NULL\n| STATS temp_files = MAX(postgresql.db_size), temp_io = SUM(RATE(postgresql.bgwriter.buffers.writes)) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend)\n| SORT time_bucket ASC'
  patch_panel 'Tuples Inserted/sec' 'Database Count' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.database.count IS NOT NULL\n| STATS database_count = MAX(postgresql.database.count)'
  patch_panel 'Tuples Returned/sec' 'Table Count' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.table.count IS NOT NULL\n| STATS table_count = MAX(postgresql.table.count)'
  patch_panel 'Tuple Throughput Over Time' 'Database and Table Count Over Time' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.database.count IS NOT NULL OR postgresql.table.count IS NOT NULL\n| STATS database_count = MAX(postgresql.database.count), table_count = MAX(postgresql.table.count) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend)\n| SORT time_bucket ASC'
  patch_panel 'Tuple Operations by Type' 'Database and Table Count by Database' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.database.count IS NOT NULL OR postgresql.table.count IS NOT NULL\n| STATS database_count = MAX(postgresql.database.count), table_count = MAX(postgresql.table.count) BY resource.attributes.postgresql.database.name\n| SORT database_count DESC'
  patch_panel 'Total Locks' 'Database Count' $'FROM metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.database.count IS NOT NULL\n| STATS database_count = MAX(postgresql.database.count)'
  patch_panel 'Locks by Type' 'Table Count by Database' $'FROM metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.table.count IS NOT NULL\n| STATS table_count = MAX(postgresql.table.count) BY resource.attributes.postgresql.database.name\n| SORT table_count DESC\n| LIMIT 10'
  patch_panel 'Locks by Mode' 'Database Size by Database' $'FROM metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.db_size IS NOT NULL\n| STATS db_size = MAX(postgresql.db_size) BY resource.attributes.postgresql.database.name\n| SORT db_size DESC\n| LIMIT 10'
  patch_panel 'Locks Over Time by Type' 'Database Count Over Time' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.database.count IS NOT NULL\n| STATS database_count = MAX(postgresql.database.count) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend)\n| SORT time_bucket ASC'
  patch_panel 'Top Relations by Lock Count' 'Top Databases by Table Count' $'FROM metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.table.count IS NOT NULL\n| STATS table_count = MAX(postgresql.table.count) BY resource.attributes.postgresql.database.name\n| SORT table_count DESC\n| LIMIT 10'
  patch_panel 'Temp Files Created' 'Database Size' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.db_size IS NOT NULL\n| STATS db_size = MAX(postgresql.db_size)'
  patch_panel 'Temp I/O (bytes)' 'Buffer Writes' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.bgwriter.buffers.writes IS NOT NULL\n| STATS writes = MAX(postgresql.bgwriter.buffers.writes)'
  patch_panel 'Temp Files Over Time' 'Database Size Over Time' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.db_size IS NOT NULL\n| STATS db_size = MAX(postgresql.db_size) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend), resource.attributes.postgresql.database.name\n| SORT time_bucket ASC'
  patch_panel 'Temp I/O Over Time' 'Buffer Writes Rate Over Time' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.bgwriter.buffers.writes IS NOT NULL\n| STATS writes = SUM(RATE(postgresql.bgwriter.buffers.writes)) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend), resource.attributes.postgresql.database.name\n| SORT time_bucket ASC'
  patch_panel 'Buffer Writes by Source' 'Buffer Writes by Database' $'FROM metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.bgwriter.buffers.writes IS NOT NULL\n| STATS writes = SUM(TO_DOUBLE(postgresql.bgwriter.buffers.writes)) BY resource.attributes.postgresql.database.name\n| SORT writes DESC\n| LIMIT 10'
  patch_panel 'Checkpoint Duration Over Time' 'Checkpoint Duration by Database' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.bgwriter.duration IS NOT NULL\n| STATS duration = SUM(RATE(postgresql.bgwriter.duration)) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend), resource.attributes.postgresql.database.name\n| SORT time_bucket ASC'
  patch_panel 'Buffer Writes Rate by Source' 'Buffer Writes Rate by Database' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.bgwriter.buffers.writes IS NOT NULL\n| STATS writes = SUM(RATE(postgresql.bgwriter.buffers.writes)) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend), resource.attributes.postgresql.database.name\n| SORT time_bucket ASC'
  patch_panel 'Top Queries by Execution Time (Delta)' 'Top Databases by Commit Rate' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.commits IS NOT NULL\n| STATS commits = SUM(RATE(postgresql.commits)) BY resource.attributes.postgresql.database.name\n| SORT commits DESC\n| LIMIT 20'
  patch_panel 'Top Queries by Call Volume' 'Top Databases by Rollback Rate' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.rollbacks IS NOT NULL\n| STATS rollbacks = SUM(RATE(postgresql.rollbacks)) BY resource.attributes.postgresql.database.name\n| SORT rollbacks DESC\n| LIMIT 20'
  patch_panel 'Active Query Count' 'Active Connections' $'TS metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.backends IS NOT NULL\n| STATS connections = SUM(LAST_OVER_TIME(postgresql.backends))'
  patch_panel 'Queries by State' 'Connections by Database' $'FROM metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.backends IS NOT NULL\n| STATS backends = MAX(postgresql.backends) BY resource.attributes.postgresql.database.name\n| SORT backends DESC\n| LIMIT 10'
  patch_panel 'Queries by Wait Event Type' 'Database Size by Database' $'FROM metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.db_size IS NOT NULL\n| STATS db_size = MAX(postgresql.db_size) BY resource.attributes.postgresql.database.name\n| SORT db_size DESC\n| LIMIT 10'
  patch_panel 'Active Queries Table' 'Recent PostgreSQL Metrics' $'FROM metrics-postgresqlreceiver.otel-*\n| KEEP @timestamp, resource.attributes.postgresql.database.name, postgresql.backends, postgresql.connection.max, postgresql.db_size\n| SORT @timestamp DESC\n| LIMIT 100'
  patch_panel 'Buffer Hit Ratio Gauge' 'Connection Utilization Gauge' $'FROM metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.backends IS NOT NULL AND postgresql.connection.max IS NOT NULL\n| STATS utilization = MAX(postgresql.backends) / MAX(postgresql.connection.max)\n| EVAL min_val = 0.0, max_val = 1.0'
  patch_panel 'Database Size Gauge' 'Connection Utilization Gauge' $'FROM metrics-postgresqlreceiver.otel-*\n| WHERE postgresql.backends IS NOT NULL AND postgresql.connection.max IS NOT NULL\n| STATS utilization = MAX(postgresql.backends) / MAX(postgresql.connection.max)\n| EVAL min_val = 0.0, max_val = 1.0'
  repair_panel_visualization 'Rollback Rate Over Time' 'time'
  repair_panel_visualization 'Database and Table Count by Database' 'database'
  repair_panel_visualization 'Connection Utilization Gauge' 'gauge'
  repair_panel_visualization 'Database Count Over Time' 'time'

  attributes="$(jq -c '.attributes' <<<"${dashboard_json}")"
  curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -H 'kbn-xsrf: systemlens-otel-dashboard-queries' \
    -X PUT "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}" \
    --data "$(jq -cn --argjson attributes "${attributes}" '{attributes:$attributes}')" \
    >/dev/null
  record_dashboard_reconciliation "${dashboard_id}" "requêtes ES|QL et configuration Lens PostgreSQL OTel"

  printf 'Requêtes PostgreSQL OTel réconciliées : %s\n' "${dashboard_id}"
done
