#!/usr/bin/env bash
# Enrôle les VM gérées par Fleet sans exposer le jeton dans le terminal.
set -euo pipefail

readonly kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
readonly kibana_user="${KIBANA_USERNAME:-elastic}"
readonly kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:192.168.33.40}"
readonly fleet_vm_nodes="poc-01 otel-backend-01 otel-edge-01"

: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de provisionner les VM Fleet}"

# La policy des VM est créée par l'API Kibana, car Kibana n'est plus réconcilié
# par ECK depuis le déplacement du stack sur elk-01.
for policy_id in data-fleet otel-fleet; do
  curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    -H 'kbn-xsrf: systemlens-fleet-policy' \
    -H 'Content-Type: application/json' \
    -X PUT \
    --data "{\"name\":\"${policy_id}\",\"namespace\":\"default\",\"monitoring_enabled\":[\"logs\",\"metrics\"]}" \
    "${kibana_url}/api/fleet/agent_policies/${policy_id}" >/dev/null
done

# Le jeton ne transite que dans l'environnement du sous-processus Vagrant.
# Le jeton ne transite jamais sur la ligne de commande ni dans le dépôt.
for node in ${fleet_vm_nodes}; do
  if [[ "${node}" == 'poc-01' ]]; then
    policy_id='data-fleet'
  else
    policy_id='otel-fleet'
  fi
  token_name="systemlens-${policy_id}-$(date +%s)"
  response="$(curl --fail --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    -H 'kbn-xsrf: systemlens-fleet-vm-provision' \
    -H 'Content-Type: application/json' \
    -X POST \
    --data "{\"name\":\"${token_name}\",\"policy_id\":\"${policy_id}\"}" \
    "${kibana_url}/api/fleet/enrollment_api_keys")"
  token="$(jq -er '.item.api_key' <<<"${response}")"
  FLEET_ENROLLMENT_TOKEN="${token}" vagrant provision "${node}"
done
