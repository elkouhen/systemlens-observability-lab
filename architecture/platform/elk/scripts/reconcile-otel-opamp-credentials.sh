#!/usr/bin/env bash
# Crée ou réutilise la clé Fleet utilisée par les collecteurs OTel Kubernetes.
set -euo pipefail

: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de réconcilier la clé OpAMP}"
: "${KUBECTL:?Définir KUBECTL vers kubectl}"

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:192.168.33.40}"
namespace="${K8S_NAMESPACE:-elastic-stack}"
secret_name='otel-fleet-opamp-credentials'
key_name='systemlens-otel-collectors'
policy_id='otel-kubernetes-otel'

curl_args=(
  --fail --silent --show-error --insecure
  --resolve "${kibana_resolve}"
  -u "${kibana_user}:${KIBANA_PASSWORD}"
  -H 'kbn-xsrf: systemlens-otel-opamp'
  -H 'Content-Type: application/json'
)

enrollment_keys="$(curl "${curl_args[@]}" "${kibana_url}/api/fleet/enrollment_api_keys?perPage=1000")"

policy_payload='{"name":"systemlens-otel-kubernetes","namespace":"default","monitoring_enabled":["logs","metrics"]}'
policies="$(curl "${curl_args[@]}" "${kibana_url}/api/fleet/agent_policies?perPage=1000")"
if jq -e --arg id "${policy_id}" '.items[]? | select(.id == $id)' >/dev/null <<<"${policies}"; then
  curl "${curl_args[@]}" -X PUT \
    --data "${policy_payload}" \
    "${kibana_url}/api/fleet/agent_policies/${policy_id}" >/dev/null
else
  curl "${curl_args[@]}" -X POST \
    --data "$(jq --arg id "${policy_id}" '. + {id: $id}' <<<"${policy_payload}")" \
    "${kibana_url}/api/fleet/agent_policies" >/dev/null
fi
api_key="$(jq -r --arg name "${key_name}" --arg policy_id "${policy_id}" '
  [.items[]? | select((.name | startswith($name)) and .policy_id == $policy_id and .active == true) | .api_key] | first // empty
' <<<"${enrollment_keys}")"

if [[ -z "${api_key}" ]]; then
  response="$(curl "${curl_args[@]}" -X POST \
    --data "$(jq -nc --arg name "${key_name}" --arg policy_id "${policy_id}" '{name:$name,policy_id:$policy_id}')" \
    "${kibana_url}/api/fleet/enrollment_api_keys")"
  api_key="$(jq -er '.item.api_key // .api_key' <<<"${response}")"
fi

kubectl_args=("${KUBECTL}" -n "${namespace}")
"${kubectl_args[@]}" create secret generic "${secret_name}" \
  --from-literal=api-key="${api_key}" \
  --dry-run=client -o yaml | "${kubectl_args[@]}" apply -f - >/dev/null

printf 'Secret OpAMP Fleet réconcilié dans %s/%s.\n' "${namespace}" "${secret_name}"
