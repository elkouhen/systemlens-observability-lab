#!/usr/bin/env bash
# Vérifie que les sources des dashboards d'observabilité publient des données.
set -euo pipefail

: "${ELASTICSEARCH_PASSWORD:?Définir ELASTICSEARCH_PASSWORD avant la vérification}"

elasticsearch_url="${ELASTICSEARCH_URL:-https://elasticsearch.poc.test:443}"
elasticsearch_user="${ELASTICSEARCH_USERNAME:-elastic}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.poc.test:443:127.0.0.1}"
window="${DASHBOARDS_VERIFY_WINDOW:-15m}"

response="$(curl --fail --silent --show-error --insecure \
  --resolve "${elasticsearch_resolve}" \
  -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${elasticsearch_url}/metrics-*,traces-*/_search" \
  --data "{\"size\":10000,\"query\":{\"bool\":{\"filter\":[{\"term\":{\"data_stream.type\":\"metrics\"}},{\"range\":{\"@timestamp\":{\"gte\":\"now-${window}\"}}}]}},\"_source\":[\"data_stream.dataset\",\"metrics\"],\"aggs\":{\"datasets\":{\"terms\":{\"field\":\"data_stream.dataset\",\"size\":100}}}}")"

expected_datasets=(hostmetricsreceiver.otel kafka.otel mongodb.otel postgresql.otel service_transaction.1m.otel)
expected_metrics=(
  system.cpu.utilization system.memory.utilization system.filesystem.usage system.network.io
  kafka.brokers kafka.partition.current_offset kafka.consumer_group.lag
  mongodb.connection.count mongodb.operation.count mongodb.storage.size
  postgresql.backends postgresql.commits postgresql.db_size
)

missing=0
for dataset in "${expected_datasets[@]}"; do
  count="$(jq -r --arg dataset "${dataset}" \
    '[.aggregations.datasets.buckets[] | select(.key == $dataset) | .doc_count] | first // 0' <<<"${response}")"
  if (( count > 0 )); then
    printf 'OK      %-28s %s document(s) sur %s\n' "${dataset}" "${count}" "${window}"
  else
    printf 'ABSENT  %-28s aucun document sur %s\n' "${dataset}" "${window}" >&2
    missing=1
  fi
done

for metric in "${expected_metrics[@]}"; do
  dataset="${metric%%.*}"
  if [[ "${dataset}" == system ]]; then
    dataset=hostmetricsreceiver
  fi
  metric_response="$(curl --fail --silent --show-error --insecure \
    --resolve "${elasticsearch_resolve}" \
    -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X POST "${elasticsearch_url}/metrics-${dataset}.otel-*/_search" \
    --data "{\"size\":10000,\"query\":{\"range\":{\"@timestamp\":{\"gte\":\"now-${window}\"}}},\"_source\":[\"metrics\"]}")"
  count="$(jq -r --arg metric "${metric}" \
    '[.hits.hits[]._source.metrics? | objects | keys[] | select(. == $metric)] | length' <<<"${metric_response}")"
  if (( count > 0 )); then
    printf 'OK      métrique %-24s %s occurrence(s) sur %s\n' "${metric}" "${count}" "${window}"
  else
    printf 'ABSENT  métrique %-24s aucune occurrence sur %s\n' "${metric}" "${window}" >&2
    missing=1
  fi
done

if (( missing )); then
  printf 'Au moins un jeu de données attendu est absent : consulter Fleet > Agents et les logs du collecteur concerné.\n' >&2
  exit 1
fi

printf 'Les sources de données des dashboards sont toutes alimentées.\n'
