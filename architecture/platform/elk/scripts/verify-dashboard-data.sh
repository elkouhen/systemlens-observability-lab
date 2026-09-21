#!/usr/bin/env bash
# Vérifie que les sources des dashboards d'observabilité publient des données.
set -euo pipefail

: "${ELASTICSEARCH_PASSWORD:?Définir ELASTICSEARCH_PASSWORD avant la vérification}"

elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
elasticsearch_user="${ELASTICSEARCH_USERNAME:-elastic}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:192.168.33.40}"
window="${DASHBOARDS_VERIFY_WINDOW:-15m}"

response="$(curl --fail --silent --show-error --insecure \
  --resolve "${elasticsearch_resolve}" \
  -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${elasticsearch_url}/metrics-*,traces-*,logs-*/_search" \
  --data "{\"size\":10000,\"query\":{\"range\":{\"@timestamp\":{\"gte\":\"now-${window}\"}}},\"_source\":[\"data_stream.dataset\",\"metrics\"],\"aggs\":{\"datasets\":{\"terms\":{\"field\":\"data_stream.dataset\",\"size\":100}}}}")"

expected_datasets=(
  hostmetricsreceiver.otel kubeletstatsreceiver.otel k8sclusterreceiver.otel generic.otel
  apm.service_transaction.1m
  kafkametricsreceiver.otel mongodbreceiver.otel postgresqlreceiver.otel
)
expected_metrics=(
  'metrics-hostmetricsreceiver.otel-*|system.cpu.utilization'
  'metrics-hostmetricsreceiver.otel-*|system.memory.utilization'
  'metrics-hostmetricsreceiver.otel-*|system.disk.io'
  'metrics-hostmetricsreceiver.otel-*|system.network.connections'
  'metrics-kafkametricsreceiver.otel-*|kafka.brokers'
  'metrics-kafkametricsreceiver.otel-*|kafka.topic.partitions'
  'metrics-kafkametricsreceiver.otel-*|kafka.consumer_group.lag'
  'metrics-mongodbreceiver.otel-*|mongodb.connection.count'
  'metrics-mongodbreceiver.otel-*|mongodb.operation.count'
  'metrics-mongodbreceiver.otel-*|mongodb.storage.size'
  'metrics-postgresqlreceiver.otel-*|postgresql.backends'
  'metrics-postgresqlreceiver.otel-*|postgresql.commits'
  'metrics-postgresqlreceiver.otel-*|postgresql.db_size'
)
expected_apm_fields=(
  service.name
  service.node.name
  host.name
  kubernetes.pod.name
  kubernetes.pod.uid
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

for field in "${expected_apm_fields[@]}"; do
  apm_response="$(curl --fail --silent --show-error --insecure \
    --resolve "${elasticsearch_resolve}" \
    -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X POST "${elasticsearch_url}/traces-apm-*/_count" \
    --data "{\"query\":{\"bool\":{\"filter\":[{\"range\":{\"@timestamp\":{\"gte\":\"now-${window}\"}}},{\"exists\":{\"field\":\"${field}\"}}]}}}")"
  count="$(jq -r '.count // 0' <<<"${apm_response}")"
  if (( count > 0 )); then
    printf 'OK      APM %-24s %s trace(s) sur %s\n' "${field}" "${count}" "${window}"
  else
    printf 'ABSENT  APM %-24s aucune trace sur %s\n' "${field}" "${window}" >&2
    missing=1
  fi
done

if (( missing )); then
  printf 'Au moins une source, métrique ou corrélation APM attendue est absente : consulter Fleet, les logs du collecteur et le mapping OTLP.\n' >&2
  exit 1
fi

printf 'Les sources de données des dashboards sont toutes alimentées.\n'
