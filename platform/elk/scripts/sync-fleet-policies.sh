#!/usr/bin/env bash
# Synchronise les pipelines Elasticsearch et les package policies qui doivent
# mettre à jour une policy Fleet déjà existante. Les secrets restent hors du
# dépôt.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elk_dir="$(cd "${script_dir}/.." && pwd)"
elasticsearch_url="${ELASTICSEARCH_URL:-https://elasticsearch.poc.test}"
: "${ELASTICSEARCH_PASSWORD:?Definir ELASTICSEARCH_PASSWORD avant de synchroniser les pipelines}"
kibana_url="${KIBANA_URL:-https://kibana.poc.test}"
kibana_password="${KIBANA_PASSWORD:-${ELASTICSEARCH_PASSWORD}}"

elasticsearch_args=(--fail --silent --show-error --insecure
  --resolve elasticsearch.poc.test:443:127.0.0.1
  -u "elastic:${ELASTICSEARCH_PASSWORD}" -H 'Content-Type: application/json')
kibana_args=(--fail --silent --show-error --insecure
  --resolve "${KIBANA_HOST:-kibana.poc.test}:443:127.0.0.1"
  -u "elastic:${kibana_password}" -H 'Content-Type: application/json'
  -H 'kbn-xsrf: systemlens-fleet-sync')

# Les package policies Fleet sont préconfigurées par Kibana dans les manifests
# Kubernetes. Ce script ne gère que les pipelines Elasticsearch @custom qui
# complètent les dashboards, afin de conserver une source de vérité IAC unique.

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

# APM 8.11 appelle le hook global metrics-apm.app@custom pour chaque metrique
# applicative. Le pipeline route tous les services executes en conteneur vers
# metrics-apm.app.kubernetes-local-<service.environment>. APM Server n'a pas de
# container.id : ses metriques, ainsi que les traces et erreurs, conservent leur
# data stream standard.
pipeline='metrics-apm.app@custom'
curl "${elasticsearch_args[@]}" -X PUT \
  "${elasticsearch_url}/_ingest/pipeline/${pipeline}" \
  --data-binary "@${elk_dir}/fleet/apm-application-metrics-reroute-pipeline.json" >/dev/null
printf 'APM application metrics reroute pipelines updated\n'

# Les applications utilisent exclusivement l'agent Java Elastic APM. Retirer
# le pipeline de traces hérité s'il est encore présent.
if curl "${elasticsearch_args[@]}" \
  "${elasticsearch_url}/_ingest/pipeline/traces-apm@custom" >/dev/null 2>&1; then
  curl "${elasticsearch_args[@]}" -X DELETE \
    "${elasticsearch_url}/_ingest/pipeline/traces-apm@custom" >/dev/null
  printf 'Legacy traces pipeline removed\n'
fi

# Les logs stdout des applications sont collectes par l'Agent Kubernetes dans
# logs-kubernetes.container_logs. Ce pipeline les route par cluster et
# environnement : le namespace reprend exactement service.environment
# (<nom-cluster>-<nom-environnement>), dans un data stream Kubernetes dont le
# template existe.
pipeline='logs-kubernetes.container_logs@custom'
curl "${elasticsearch_args[@]}" -X PUT \
  "${elasticsearch_url}/_ingest/pipeline/${pipeline}" \
  --data-binary "@${elk_dir}/fleet/kubernetes-application-logs-reroute-pipeline.json" >/dev/null
printf 'Kubernetes application logs reroute pipeline updated\n'

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

# Les package policies préconfigurées par Kibana ne sont créées qu'une fois.
# Mettre à jour explicitement la policy existante conserve la source de vérité
# Kubernetes tout en diffusant une correction aux Agents déjà enrôlés.
postgresql_policy="$(curl "${kibana_args[@]}" \
  "${kibana_url}/api/fleet/package_policies/postgresql-data-01")"
postgresql_payload="$(jq '
  .item
  | {name, namespace, policy_id, package, inputs}
  | .inputs |= map(
      if .type == "postgresql/metrics" then
        .vars.condition = {
          type: "text",
          value: "${host.name} == '\''data-01'\''"
        }
      else . end
    )
' <<<"${postgresql_policy}")"
curl "${kibana_args[@]}" -X PUT \
  "${kibana_url}/api/fleet/package_policies/postgresql-data-01" \
  --data "${postgresql_payload}" >/dev/null
printf 'PostgreSQL package policy updated for data-01 only\n'
