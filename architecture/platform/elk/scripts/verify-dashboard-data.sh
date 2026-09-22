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
  'metrics-postgresqlreceiver.otel-*|postgresql.connection.max'
  'metrics-postgresqlreceiver.otel-*|postgresql.commits'
  'metrics-postgresqlreceiver.otel-*|postgresql.rollbacks'
  'metrics-postgresqlreceiver.otel-*|postgresql.database.count'
  'metrics-postgresqlreceiver.otel-*|postgresql.table.count'
  'metrics-postgresqlreceiver.otel-*|postgresql.db_size'
  'metrics-postgresqlreceiver.otel-*|postgresql.bgwriter.maxwritten'
  'metrics-postgresqlreceiver.otel-*|postgresql.bgwriter.buffers.allocated'
  'metrics-postgresqlreceiver.otel-*|postgresql.bgwriter.buffers.writes'
  'metrics-postgresqlreceiver.otel-*|postgresql.bgwriter.checkpoint.count'
  'metrics-postgresqlreceiver.otel-*|postgresql.bgwriter.duration'
)
expected_apm_fields=(
  service.name
  service.node.name
  host.name
  kubernetes.pod.name
  kubernetes.pod.uid
)

missing=0
ko_metrics=()
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
    printf 'KO      métrique %-24s aucune occurrence sur %s\n' "${metric}" "${window}" >&2
    ko_metrics+=("${metric}")
    missing=1
  fi
done

hostmetrics_response="$(curl --fail --silent --show-error --insecure \
  --resolve "${elasticsearch_resolve}" \
  -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -X POST "${elasticsearch_url}/metrics-hostmetricsreceiver.otel-*/_search" \
  --data "{\"size\":0,\"query\":{\"bool\":{\"filter\":[{\"range\":{\"@timestamp\":{\"gte\":\"now-${window}\"}}},{\"term\":{\"data_stream.dataset\":\"hostmetricsreceiver.otel\"}},{\"exists\":{\"field\":\"host.name\"}},{\"exists\":{\"field\":\"system.cpu.utilization\"}}]}},\"aggs\":{\"hosts\":{\"terms\":{\"field\":\"host.name\",\"size\":20}}}}")"
expected_hostmetrics_hosts=(poc-01 otel-backend-01 otel-edge-01 elk-01)
for host in "${expected_hostmetrics_hosts[@]}"; do
  host_count="$(jq -r --arg host "${host}" \
    '[.aggregations.hosts.buckets[] | select(.key == $host) | .doc_count] | first // 0' <<<"${hostmetrics_response}")"
  if (( host_count > 0 )); then
    printf 'OK      hôte Inventory %-18s %s document(s) sur %s\n' "${host}" "${host_count}" "${window}"
  else
    printf 'ABSENT  hôte Inventory %-18s aucun document CPU sur %s\n' "${host}" "${window}" >&2
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
  if (( ${#ko_metrics[@]} > 0 )); then
    printf 'Métriques KO détectées : %s\n' "${ko_metrics[*]}" >&2
  fi
  printf 'Au moins une source, métrique ou corrélation APM attendue est absente : consulter Fleet, les logs du collecteur et le mapping OTLP.\n' >&2
  exit 1
fi

printf 'Les sources de données des dashboards sont toutes alimentées.\n'
