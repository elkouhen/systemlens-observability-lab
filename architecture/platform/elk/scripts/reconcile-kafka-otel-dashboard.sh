#!/usr/bin/env bash
# Corrige le comptage des brokers dans le dashboard Kafka OTel du package Fleet.
set -euo pipefail

command -v curl >/dev/null || { printf 'curl est requis.\n' >&2; exit 2; }
command -v jq >/dev/null || { printf 'jq est requis.\n' >&2; exit 2; }

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:192.168.33.40}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de réconcilier le dashboard Kafka OTel}"

curl_args=(--fail --silent --show-error --insecure --resolve "${kibana_resolve}"
  -u "elastic:${KIBANA_PASSWORD}" -H 'kbn-xsrf: systemlens-kafka-dashboard'
  -H 'Content-Type: application/json')

dashboard_id="$(curl "${curl_args[@]}" \
  "${kibana_url}/api/saved_objects/_find?type=dashboard&per_page=100&search_fields=title&search=Kafka%20OTel" |
  jq -er '.saved_objects[] | select(.attributes.title == "[Kafka OTel] Overview") | .id' | head -n 1)"

dashboard="$(curl "${curl_args[@]}" \
  "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}")"

old_query='TS metrics-kafkametricsreceiver.otel-*
| WHERE data_stream.dataset == "kafkametricsreceiver.otel"
| WHERE kafka.brokers IS NOT NULL
| STATS brokers = MAX(LAST_OVER_TIME(kafka.brokers)) BY time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend)
| SORT time_bucket ASC'
new_query='TS metrics-kafkametricsreceiver.otel-*
| WHERE data_stream.dataset == "kafkametricsreceiver.otel"
| WHERE kafka.brokers IS NOT NULL
| STATS brokers_per_host = MAX(LAST_OVER_TIME(kafka.brokers)) BY resource.attributes.host.name, time_bucket = BUCKET(@timestamp, 20, ?_tstart, ?_tend)
| STATS brokers = SUM(brokers_per_host) BY time_bucket
| SORT time_bucket ASC'

old_count="$(jq --arg old "${old_query}" '
  [.attributes.panelsJSON | fromjson | .. | strings | select(. == $old)] | length
' <<<"${dashboard}")"
new_count="$(jq --arg new "${new_query}" '
  [.attributes.panelsJSON | fromjson | .. | strings | select(. == $new)] | length
' <<<"${dashboard}")"
if (( old_count == 0 && new_count > 0 )); then
  printf 'Dashboard Kafka OTel déjà réconcilié : le nombre de brokers est sommé par hôte.\n'
  exit 0
fi

panels_json="$(jq -er --arg old "${old_query}" --arg new "${new_query}" '
  .attributes.panelsJSON
  | fromjson
  | walk(if type == "string" and . == $old then $new else . end)
  | tojson
' <<<"${dashboard}")"

(( old_count > 0 )) || {
  printf 'Requête Broker Count Over Time introuvable dans le dashboard %s.\n' "${dashboard_id}" >&2
  exit 1
}

payload="$(jq -c --arg panels_json "${panels_json}" \
  '{attributes: (.attributes | .panelsJSON = $panels_json), references: .references}' <<<"${dashboard}")"
curl "${curl_args[@]}" -X PUT \
  "${kibana_url}/api/saved_objects/dashboard/${dashboard_id}" \
  --data "${payload}" >/dev/null

printf 'Dashboard Kafka OTel réconcilié : le nombre de brokers est sommé par hôte.\n'
