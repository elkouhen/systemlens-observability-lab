#!/usr/bin/env bash
# Vérifie la propagation W3C et le contrat ECS/OTel sur les données indexées.
set -euo pipefail

: "${ELASTICSEARCH_PASSWORD:?Définir ELASTICSEARCH_PASSWORD avant la vérification}"

mode="${1:-}"
case "${mode}" in
  schema|trace-context) ;;
  *)
    printf 'Usage : %s schema|trace-context\n' "$0" >&2
    exit 2
    ;;
esac

elasticsearch_url="${ELASTICSEARCH_URL:-http://elasticsearch.observability.test:9200}"
elasticsearch_user="${ELASTICSEARCH_USERNAME:-elastic}"
elasticsearch_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.observability.test:9200:192.168.33.40}"
window="${OBSERVABILITY_VERIFY_WINDOW:-30m}"

request() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "${body}" ]]; then
    curl --fail --silent --show-error --insecure \
      --resolve "${elasticsearch_resolve}" \
      -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
      -H 'Content-Type: application/json' \
      -X "${method}" "${elasticsearch_url}${path}" \
      --data "${body}"
  else
    curl --fail --silent --show-error --insecure \
      --resolve "${elasticsearch_resolve}" \
      -u "${elasticsearch_user}:${ELASTICSEARCH_PASSWORD}" \
      -X "${method}" "${elasticsearch_url}${path}"
  fi
}

count_query() {
  local pattern="$1" query="$2"
  request POST "/${pattern}/_count" "${query}" | jq -r '.count // 0'
}

failures=0
check_zero() {
  local label="$1" count="$2"
  if [[ "${count}" == 0 ]]; then
    printf 'OK      %s\n' "${label}"
  else
    printf 'KO      %s : %s document(s)\n' "${label}" "${count}" >&2
    failures=1
  fi
}

if [[ "${mode}" == trace-context ]]; then
  properties_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../../kubernetes/apps/supermarket-demo/default/otel" && pwd)"
  for service in order-service inventory-service restock-service; do
    properties_file="${properties_dir}/${service}.properties"
    grep -Eq '^otel\.propagators=tracecontext,baggage$' "${properties_file}" || {
      printf 'KO      propagateurs W3C absents de %s\n' "${properties_file}" >&2
      failures=1
    }
  done
  if [[ "${failures}" == 0 ]]; then
    printf 'OK      propagateurs W3C tracecontext,baggage configurés pour les trois services\n'
  fi

  trace_query="$(jq -cn --arg window "${window}" '{
    size: 0,
    query: {range: {"@timestamp": {gte: ("now-" + $window)}}},
    aggs: {
      trace_ids: {
        terms: {field: "trace.id", size: 500, min_doc_count: 2},
        aggs: {
          services: {terms: {field: "service.name", size: 20}},
          kafka: {filter: {bool: {should: [
            {term: {"span.subtype": "kafka"}},
            {term: {"span.type": "messaging"}},
            {wildcard: {"span.name": "*kafka*"}}
          ], minimum_should_match: 1}}}
        }
      }
    }
  }')"
  trace_response="$(request POST '/traces-*/_search' "${trace_query}")"
  trace_id="$(jq -r '[.aggregations.trace_ids.buckets[]
    | select(([.services.buckets[].key] | index("order-service")) != null)
    | select(([.services.buckets[].key] | index("inventory-service")) != null)
    | select(.kafka.doc_count > 0)
    | .key] | first // empty' <<<"${trace_response}")"
  if [[ -z "${trace_id}" ]]; then
    printf 'KO      aucun trace.id ne relie order-service, inventory-service et un span Kafka sur %s\n' "${window}" >&2
    failures=1
  else
    printf 'OK      trace.id partagé entre REST/Kafka et les services applicatifs sur %s\n' "${window}"
    logs_query="$(jq -cn --arg trace_id "${trace_id}" --arg window "${window}" '{
      query: {bool: {filter: [
        {range: {"@timestamp": {gte: ("now-" + $window)}}},
        {term: {"trace.id": $trace_id}}
      ]}}
    }')"
    logs_count="$(count_query 'logs-*' "${logs_query}")"
    if (( logs_count > 0 )); then
      printf 'OK      logs corrélés avec le trace.id sélectionné : %s document(s)\n' "${logs_count}"
    else
      printf 'KO      aucun log corrélé avec le trace.id sélectionné\n' >&2
      failures=1
    fi
  fi
fi

if [[ "${mode}" == schema ]]; then
  common_missing_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [{range: {"@timestamp": {gte: ("now-" + $window)}}}],
      should: [
        {bool: {must_not: [{exists: {field: "@timestamp"}}]}},
        {bool: {must_not: [{exists: {field: "data_stream.dataset"}}]}}
      ],
      minimum_should_match: 1
    }}
  }')"
  common_missing="$(count_query 'logs-*,metrics-*,traces-*' "${common_missing_query}")"
  check_zero "documents sans @timestamp ou data_stream.dataset" "${common_missing}"

  trace_missing_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [
        {range: {"@timestamp": {gte: ("now-" + $window)}}},
        {exists: {field: "span.name"}}
      ],
      should: [
        {bool: {must_not: [{exists: {field: "trace.id"}}]}},
        {bool: {must_not: [{exists: {field: "span.id"}}]}}
      ],
      minimum_should_match: 1
    }}
  }')"
  trace_missing="$(count_query 'traces-*' "${trace_missing_query}")"
  check_zero "spans sans trace.id ou span.id" "${trace_missing}"

  service_missing_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [
        {range: {"@timestamp": {gte: ("now-" + $window)}}},
        {exists: {field: "data_stream.dataset"}}
      ],
      must_not: [{exists: {field: "service.name"}}]
    }}
  }')"
  service_missing="$(count_query 'traces-*,metrics-generic.otel-*,logs-generic.otel-*' "${service_missing_query}")"
  check_zero "documents OTel applicatifs sans service.name" "${service_missing}"

  ecs_missing_query="$(jq -cn --arg window "${window}" '{
    query: {bool: {
      filter: [
        {range: {"@timestamp": {gte: ("now-" + $window)}}},
        {exists: {field: "service.name"}}
      ],
      must_not: [{exists: {field: "ecs.version"}}]
    }}
  }')"
  ecs_missing="$(count_query 'logs-generic.otel-*' "${ecs_missing_query}")"
  check_zero "logs applicatifs sans ecs.version" "${ecs_missing}"
fi

if (( failures )); then
  printf 'Contrôle d’observabilité en échec. Fenêtre contrôlée : %s\n' "${window}" >&2
  exit 1
fi

printf 'Contrôle d’observabilité réussi. Fenêtre contrôlée : %s\n' "${window}"
