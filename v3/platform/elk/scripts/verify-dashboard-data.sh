#!/usr/bin/env bash
# Vérifie que les sources des dashboards d'observabilité publient des données.
set -euo pipefail

: "${ELASTICSEARCH_PASSWORD:?Définir ELASTICSEARCH_PASSWORD avant la vérification}"

elasticsearch_url="${ELASTICSEARCH_URL:-https://elasticsearch.observability.test:443}"
elasticsearch_user="${ELASTICSEARCH_USERNAME:-elastic}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:443:127.0.0.1}"
window="${DASHBOARDS_VERIFY_WINDOW:-15m}"

response="$(curl --fail --silent --show-error --insecure \
  --resolve "${elasticsearch_resolve}" \
  -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${elasticsearch_url}/metrics-*,traces-*/_search" \
  --data "{\"size\":10000,\"query\":{\"bool\":{\"filter\":[{\"term\":{\"data_stream.type\":\"metrics\"}},{\"range\":{\"@timestamp\":{\"gte\":\"now-${window}\"}}}]}},\"_source\":[\"data_stream.dataset\",\"metrics\"],\"aggs\":{\"datasets\":{\"terms\":{\"field\":\"data_stream.dataset\",\"size\":100}}}}")"

expected_datasets=(
  hostmetricsreceiver.otel service_transaction.1m.otel
  system.cpu system.memory system.filesystem system.network
  kafka.broker kafka.partition kafka.consumergroup
  mongodb.status mongodb.metrics mongodb.dbstats
  postgresql.database
)
expected_metrics=(
  'metrics-system.cpu-*|system.cpu.total.norm.pct'
  'metrics-system.memory-*|system.memory.actual.used.pct'
  'metrics-system.filesystem-*|system.filesystem.used.bytes'
  'metrics-system.network-*|system.network.in.bytes'
  'metrics-kafka.broker-*|kafka.broker.topic.net.out.bytes_per_sec'
  'metrics-kafka.partition-*|kafka.partition.offset.newest'
  'metrics-kafka.consumergroup-*|kafka.consumergroup.consumer_lag'
  'metrics-mongodb.status-*|mongodb.status.connections.current'
  'metrics-mongodb.status-*|mongodb.status.ops.counters.command'
  'metrics-mongodb.dbstats-*|mongodb.dbstats.storage_size.bytes'
  'metrics-postgresql.database-*|postgresql.database.number_of_backends'
  'metrics-postgresql.database-*|postgresql.database.transactions.commit'
  'metrics-postgresql.database-*|postgresql.database.blocks.hit'
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

for expectation in "${expected_metrics[@]}"; do
  index_pattern="${expectation%%|*}"
  metric="${expectation#*|}"
  metric_response="$(curl --fail --silent --show-error --insecure \
    --resolve "${elasticsearch_resolve}" \
    -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X POST "${elasticsearch_url}/${index_pattern}/_count" \
    --data "{\"query\":{\"bool\":{\"filter\":[{\"range\":{\"@timestamp\":{\"gte\":\"now-${window}\"}}},{\"exists\":{\"field\":\"${metric}\"}}]}}}")"
  count="$(jq -r '.count // 0' <<<"${metric_response}")"
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
