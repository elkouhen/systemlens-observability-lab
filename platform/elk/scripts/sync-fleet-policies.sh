#!/usr/bin/env bash
# Synchronise les pipelines Elasticsearch qui ne peuvent pas etre declares dans
# kibana.yml. Les package policies Fleet sont preconfigurees dans le manifest
# Kubernetes Kibana. Les secrets restent hors du depot.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elk_dir="$(cd "${script_dir}/.." && pwd)"
kibana_url="${KIBANA_URL:-https://kibana.poc.test}"
elasticsearch_url="${ELASTICSEARCH_URL:-https://elasticsearch.poc.test}"
kibana_user="${KIBANA_USERNAME:-elastic}"
: "${KIBANA_PASSWORD:?Definir KIBANA_PASSWORD avant de synchroniser Fleet}"

elasticsearch_args=(--fail --silent --show-error --insecure
  --resolve elasticsearch.poc.test:443:127.0.0.1
  -u "${kibana_user}:${KIBANA_PASSWORD}" -H 'Content-Type: application/json')

# Les pipelines @custom sont conserves lors des mises a jour de packages.
curl "${elasticsearch_args[@]}" -X PUT \
  "${elasticsearch_url}/_ingest/pipeline/metrics-kafka.topic@custom" \
  --data-binary "@${elk_dir}/fleet/kafka-topic-ingest-pipeline.json" >/dev/null
printf 'Ingest pipeline updated: metrics-kafka.topic@custom\n'

# L'endpoint Jolokia reste volontairement local à chaque VM. Les métriques
# doivent toutefois identifier le broker qui les a produites, pas localhost.
for dataset in controller jvm network log_manager replica_manager topic raft; do
  pipeline="metrics-kafka.${dataset}@custom"
  existing="$(curl "${elasticsearch_args[@]}" "${elasticsearch_url}/_ingest/pipeline/${pipeline}" 2>/dev/null || printf '{}')"
  payload="$(jq --arg pipeline "${pipeline}" '
    .[$pipeline] // {description: "Kafka custom processors", processors: []}
    # L API GET ajoute ces champs en lecture seule ; ne jamais les renvoyer
    # dans le PUT, sinon Elasticsearch repond 400.
    | del(.created_date_millis, .modified_date_millis)
    | .processors = ([.processors[] | select(.set.tag != "set-kafka-service-address")] +
        [{set: {tag: "set-kafka-service-address", field: "service.address", value: "{{{host.name}}}", override: true}}])
  ' <<<"${existing}")"
  curl "${elasticsearch_args[@]}" -X PUT \
    "${elasticsearch_url}/_ingest/pipeline/${pipeline}" \
    --data "${payload}" >/dev/null
done
printf 'Kafka service.address pipelines updated\n'
