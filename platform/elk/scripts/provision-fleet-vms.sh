#!/usr/bin/env bash
# Enrôle les VM gérées par Fleet sans exposer le jeton dans le terminal.
set -euo pipefail

readonly policy_id='data-01-02-fleet'
readonly kibana_url="${KIBANA_URL:-https://kibana.poc.test}"
readonly kibana_user="${KIBANA_USERNAME:-elastic}"
readonly kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.poc.test:443:127.0.0.1}"
readonly fleet_vm_nodes="${FLEET_VM_NODES:-data-01 data-02}"
token_name="systemlens-${policy_id}-$(date +%s)"

: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de provisionner les VM Fleet}"

response="$(curl --fail --silent --show-error --insecure \
  --resolve "${kibana_resolve}" \
  -u "${kibana_user}:${KIBANA_PASSWORD}" \
  -H 'kbn-xsrf: systemlens-fleet-vm-provision' \
  -H 'Content-Type: application/json' \
  -X POST \
  --data "{\"name\":\"${token_name}\",\"policy_id\":\"${policy_id}\"}" \
  "${kibana_url}/api/fleet/enrollment_api_keys")"

token="$(jq -er '.item.api_key' <<<"${response}")"

# Le jeton ne transite que dans l'environnement du sous-processus Vagrant.
# Le jeton ne transite jamais sur la ligne de commande ni dans le dépôt.
FLEET_ENROLLMENT_TOKEN="${token}" vagrant provision ${fleet_vm_nodes}
