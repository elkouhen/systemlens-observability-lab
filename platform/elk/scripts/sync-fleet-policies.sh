#!/usr/bin/env bash
# Synchronise les pipelines Elasticsearch et les package policies qui doivent
# mettre à jour une policy Fleet déjà existante. Les secrets restent hors du
# dépôt.
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
kibana_args=(--fail --silent --show-error --insecure
  --resolve kibana.poc.test:443:127.0.0.1
  -u "${kibana_user}:${KIBANA_PASSWORD}" -H 'Content-Type: application/json' -H 'kbn-xsrf: true')

# `xpack.fleet.agentPolicies` préconfigure une policy au premier démarrage de
# Kibana mais n'ajoute pas rétroactivement une package policy à une policy
# existante. La création est donc idempotente via l'API Fleet. Les packages
# sont volontairement laissés inchangés après création : leurs variables sont
# versionnées par l'intégration installée dans Kibana.
for package_policy in system-fleet postgresql-fleet; do
  package_name="${package_policy%-fleet}"
  package_policy_id="$(curl "${kibana_args[@]}" \
  "${kibana_url}/api/fleet/package_policies?perPage=100" \
    | jq -r --arg name "${package_policy}" '.items[] | select(.name == $name) | .id' | head -n 1)"
  if [[ -z "${package_policy_id}" ]]; then
    curl "${kibana_args[@]}" -X POST \
      "${kibana_url}/api/fleet/package_policies" \
      --data-binary "@${elk_dir}/fleet/${package_name}-package-policy.json" >/dev/null
    printf 'Fleet package policy created: %s\n' "${package_policy}"
  else
    printf 'Fleet package policy already present: %s\n' "${package_policy}"
  fi
done

# Les pipelines @custom sont conserves lors des mises a jour de packages.
curl "${elasticsearch_args[@]}" -X PUT \
  "${elasticsearch_url}/_ingest/pipeline/metrics-kafka.topic@custom" \
  --data-binary "@${elk_dir}/fleet/kafka-topic-ingest-pipeline.json" >/dev/null
printf 'Ingest pipeline updated: metrics-kafka.topic@custom\n'

# Les metriques OTel conservent leur schema natif (metrics.*), mais les
# dashboards historiques filtrent sur host.name. Le pipeline ajoute ce champ
# sans modifier les attributs de ressource OTel.
curl "${elasticsearch_args[@]}" -X PUT \
  "${elasticsearch_url}/_ingest/pipeline/otel-hostmetrics-dashboard-compat" \
  --data-binary "@${elk_dir}/fleet/otel-hostmetrics-dashboard-compat-pipeline.json" >/dev/null
printf 'Ingest pipeline updated: otel-hostmetrics-dashboard-compat\n'

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

# L'integration MongoDB se connecte volontairement a localhost sur chaque VM.
# Les dashboards groupent toutefois les instances par service.address :
# remplacer uniquement l'adresse locale par le nom de la VM rend data-01..03
# distinguables, sans reecrire les adresses de replica set deja explicites.
for dataset in collstats dbstats metrics replstatus status; do
  pipeline="metrics-mongodb.${dataset}@custom"
  existing="$(curl "${elasticsearch_args[@]}" "${elasticsearch_url}/_ingest/pipeline/${pipeline}" 2>/dev/null || printf '{}')"
  payload="$(jq --arg pipeline "${pipeline}" '
    .[$pipeline] // {description: "MongoDB custom processors", processors: []}
    | del(.created_date_millis, .modified_date_millis)
    | .processors = ([.processors[] | select(.set.tag != "set-mongodb-local-service-address")] +
        [{set: {
          tag: "set-mongodb-local-service-address",
          field: "service.address",
          value: "{{{host.name}}}",
          if: "ctx.service != null && (ctx.service.address == '\''mongodb://localhost:27017'\'' || ctx.service.address == '\''mongodb://127.0.0.1:27017'\'')",
          override: true
        }}])
  ' <<<"${existing}")"
  curl "${elasticsearch_args[@]}" -X PUT \
    "${elasticsearch_url}/_ingest/pipeline/${pipeline}" \
    --data "${payload}" >/dev/null
done
printf 'MongoDB service.address pipelines updated\n'
