#!/usr/bin/env bash
# Installe le pipeline apm-route-namespace et les pipelines @custom des data
# streams APM qui l'appellent (ADR-010, note du 2026-11-02). Le collecteur
# backend pose le label global apm_route_namespace sur les traces d'une route
# applicative ; APM Server le reporte sur ses métriques agrégées. Le pipeline
# range ces métriques dans ce namespace et retire le label de tous les
# documents APM. Les pipelines @default-pipeline gérés par Elasticsearch
# appellent <type>-<dataset>@custom avant leur traitement : le reroute y est
# permis. Les secrets restent hors du dépôt.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elk_dir="$(cd "${script_dir}/.." && pwd)"
command -v curl >/dev/null || { printf 'curl est requis.\n' >&2; exit 2; }
command -v jq >/dev/null || { printf 'jq est requis.\n' >&2; exit 2; }
elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
: "${ELASTICSEARCH_PASSWORD:?Definir ELASTICSEARCH_PASSWORD avant de synchroniser les pipelines APM}"
elasticsearch_args=(--fail --silent --show-error --insecure
  --resolve "${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:192.168.33.40}"
  -u "elastic:${ELASTICSEARCH_PASSWORD}" -H 'Content-Type: application/json')

curl "${elasticsearch_args[@]}" -X PUT \
  "${elasticsearch_url}/_ingest/pipeline/apm-route-namespace" \
  --data-binary "@${elk_dir}/ingest/apm-route-namespace.json" >/dev/null
printf 'Ingest pipeline updated: apm-route-namespace\n'

# Data streams APM qui peuvent porter le label : traces, erreurs, logs
# applicatifs dérivés des traces, métriques de l'agent OTel (ADR-016) et
# métriques agrégées (tous intervalles).
for pipeline in traces-apm@custom logs-apm.error@custom logs-apm.app@custom metrics-apm.app@custom metrics-apm.internal@custom \
  metrics-apm.transaction@custom metrics-apm.service_transaction@custom \
  metrics-apm.service_destination@custom metrics-apm.service_summary@custom; do
  jq -n --arg pipeline "${pipeline}" '{
    description: ("ADR-010 : namespace des données APM routées (" + $pipeline + ")"),
    processors: [{pipeline: {name: "apm-route-namespace"}}]
  }' | curl "${elasticsearch_args[@]}" -X PUT \
    "${elasticsearch_url}/_ingest/pipeline/${pipeline}" --data-binary @- >/dev/null
  printf 'Ingest pipeline updated: %s\n' "${pipeline}"
done
