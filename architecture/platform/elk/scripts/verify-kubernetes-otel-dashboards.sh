#!/usr/bin/env bash
# Vérifie les requêtes ES|QL des dashboards Kubernetes OTel Fleet.
set -euo pipefail

command -v curl >/dev/null || { printf 'curl est requis.\n' >&2; exit 2; }
command -v jq >/dev/null || { printf 'jq est requis.\n' >&2; exit 2; }

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:192.168.33.30}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant la vérification des dashboards Kubernetes OTel}"

response="$(curl --fail --silent --show-error --insecure --resolve "${kibana_resolve}" \
  -u "elastic:${KIBANA_PASSWORD}" \
  "${kibana_url}/api/saved_objects/_find?type=dashboard&per_page=100&search_fields=title&search=Kubernetes%20OTel" \
  | jq '{saved_objects: [.saved_objects[] | select(.attributes.title | startswith("[Kubernetes OTel]"))]}')"

count="$(jq '.saved_objects | length' <<<"${response}")"
(( count == 11 )) || { printf 'Nombre inattendu de dashboards Kubernetes OTel : %s (attendu 11).\n' "${count}" >&2; exit 1; }

for forbidden in \
  'k8s.container.status.last_terminated_reason' \
  'k8s.node.condition_memory_pressure' \
  'k8s.pod.cpu_limit_utilization' \
  'k8s.pod.memory_limit_utilization'; do
  occurrences="$(while IFS= read -r id; do
    curl --fail --silent --show-error --insecure --resolve "${kibana_resolve}" \
      -u "elastic:${KIBANA_PASSWORD}" "${kibana_url}/api/saved_objects/dashboard/${id}"
  done < <(jq -r '.saved_objects[].id' <<<"${response}") \
    | jq -r --arg field "${forbidden}" \
      '.attributes.panelsJSON | fromjson[] | .embeddableConfig.attributes.state.query.esql? // empty | select(contains($field))' \
    | wc -l | tr -d ' ' )"
  if (( occurrences > 0 )); then
    printf 'ABSENT  correction du champ %s (%s occurrence(s))\n' "${forbidden}" "${occurrences}" >&2
    exit 1
  fi
  printf 'OK      aucun panneau ne référence %s\n' "${forbidden}"
done

printf 'Les 11 dashboards Kubernetes OTel ont des requêtes compatibles avec le schéma collecté.\n'
