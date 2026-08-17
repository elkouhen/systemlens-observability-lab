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

  # Fleet 9.5 ne supporte pas le schema PUT expose par les versions
  # precedentes de l'API. La suppression suivie de la creation converge vers
  # le manifeste versionne sans laisser de doublon; les agents gardent leur
  # agent policy et recoivent la nouvelle package policy au prochain check-in.
  api -X DELETE "${kibana_url}/api/fleet/package_policies/${policy_id}" >/dev/null
  api -X POST "${kibana_url}/api/fleet/package_policies" --data-binary "@${policy_file}" >/dev/null
  printf 'Package policy replaced: %s\n' "${policy_name}"
}

sync_package_policy "${project_dir}/elastic-agent/mongodb-package-policy.json"
sync_package_policy "${project_dir}/elastic-agent/kafka-package-policy.json"
sync_package_policy "${project_dir}/elastic-agent/system-package-policy.json"
sync_package_policy "${project_dir}/elastic-agent/kafka-producer-client-package-policy.json"
sync_package_policy "${project_dir}/elastic-agent/kafka-consumer-client-package-policy.json"

# Les pipelines @custom sont conserves lors des mises a jour de packages.
curl "${elasticsearch_args[@]}" -X PUT \
  "${elasticsearch_url}/_ingest/pipeline/metrics-kafka.topic@custom" \
  --data-binary "@${project_dir}/elastic-agent/kafka-topic-ingest-pipeline.json" >/dev/null
printf 'Ingest pipeline updated: metrics-kafka.topic@custom\n'
