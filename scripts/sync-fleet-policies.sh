#!/usr/bin/env bash
# Synchronise les policies Fleet du POC. Les secrets restent hors du depot :
# KIBANA_PASSWORD doit etre fourni par l'environnement d'execution.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
kibana_url="${KIBANA_URL:-https://kibana.poc.test}"
elasticsearch_url="${ELASTICSEARCH_URL:-https://elasticsearch.poc.test}"
kibana_user="${KIBANA_USERNAME:-elastic}"
: "${KIBANA_PASSWORD:?Definir KIBANA_PASSWORD avant de synchroniser Fleet}"

curl_args=(--fail --silent --show-error --insecure
  --resolve kibana.poc.test:443:127.0.0.1
  -u "${kibana_user}:${KIBANA_PASSWORD}"
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json')

api() {
  curl "${curl_args[@]}" "$@"
}

elasticsearch_args=(--fail --silent --show-error --insecure
  --resolve elasticsearch.poc.test:443:127.0.0.1
  -u "${kibana_user}:${KIBANA_PASSWORD}" -H 'Content-Type: application/json')

ensure_agent_policy() {
  local policy_id="$1" policy_name="$2" data_output_id="${3:-}"
  if api "${kibana_url}/api/fleet/agent_policies/${policy_id}" >/dev/null 2>&1; then
    return
  fi

  local data='{"id":"'"${policy_id}"'","name":"'"${policy_name}"'","namespace":"default","monitoring_enabled":["logs","metrics"]}'
  if [[ -n "${data_output_id}" ]]; then
    data="$(jq --arg output "${data_output_id}" '. + {data_output_id: $output, monitoring_output_id: $output}' <<<"${data}")"
  fi
  api -X POST "${kibana_url}/api/fleet/agent_policies" \
    --data "${data}" \
    >/dev/null
}

ensure_agent_policy "mongodb-hosts" "MongoDB hosts"

sync_package_policy() {
  local policy_file="$1" policy_name policy_id
  policy_name="$(jq -r '.name' "${policy_file}")"
  policy_id="$(api "${kibana_url}/api/fleet/package_policies?perPage=100" | jq -r --arg name "${policy_name}" '.items[] | select(.name == $name) | .id' | head -n1)"

  if [[ -z "${policy_id}" ]]; then
    api -X POST "${kibana_url}/api/fleet/package_policies" --data-binary "@${policy_file}" >/dev/null
    printf 'Package policy created: %s\n' "${policy_name}"
    return
  fi

  # La mise a jour conserve l'identifiant de la package policy et evite une
  # fenetre sans collecte. L'API Fleet accepte le meme schema que la creation.
  api -X PUT "${kibana_url}/api/fleet/package_policies/${policy_id}" \
    --data-binary "@${policy_file}" >/dev/null
  printf 'Package policy updated: %s\n' "${policy_name}"
}

sync_package_policy "${project_dir}/elastic-agent/mongodb-package-policy.json"
sync_package_policy "${project_dir}/elastic-agent/kafka-package-policy.json"
sync_package_policy "${project_dir}/elastic-agent/system-package-policy.json"

# Les endpoints Jolokia applicatifs ne sont plus publies hors du cluster. Les
# anciennes policies doivent donc etre retirees lors de la migration, sinon
# les agents conservent des scrapes en erreur.
remove_package_policy() {
  local policy_name="$1" policy_id
  policy_id="$(api "${kibana_url}/api/fleet/package_policies?perPage=100" | jq -r --arg name "${policy_name}" '.items[] | select(.name == $name) | .id' | head -n1)"
  if [[ -n "${policy_id}" ]]; then
    api -X DELETE "${kibana_url}/api/fleet/package_policies/${policy_id}" >/dev/null
    printf 'Package policy removed: %s\n' "${policy_name}"
  fi
}

remove_package_policy "kafka-producer-client-fleet"
remove_package_policy "kafka-consumer-client-fleet"

# Les pipelines @custom sont conserves lors des mises a jour de packages.
curl "${elasticsearch_args[@]}" -X PUT \
  "${elasticsearch_url}/_ingest/pipeline/metrics-kafka.topic@custom" \
  --data-binary "@${project_dir}/elastic-agent/kafka-topic-ingest-pipeline.json" >/dev/null
printf 'Ingest pipeline updated: metrics-kafka.topic@custom\n'
