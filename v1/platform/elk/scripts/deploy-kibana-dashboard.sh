#!/usr/bin/env bash
# Importe un export NDJSON Kibana de manière idempotente.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elk_dir="$(cd "${script_dir}/.." && pwd)"
dashboard_file="${1:?Usage : $0 <export.ndjson>}"
kibana_url="${KIBANA_URL:-https://kibana.poc.test}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.poc.test:443:127.0.0.1}"

[[ -r "${dashboard_file}" ]] || {
  printf 'Fichier dashboard introuvable ou illisible : %s\n' "${dashboard_file}" >&2
  exit 1
}
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de déployer le dashboard}"

response="$(curl --fail --silent --show-error --insecure \
  --resolve "${kibana_resolve}" \
  -u "${kibana_user}:${KIBANA_PASSWORD}" \
  -H 'kbn-xsrf: systemlens-dashboard-deploy' \
  -F "file=@${dashboard_file};type=application/ndjson" \
  "${kibana_url}/api/saved_objects/_import?overwrite=true")"

if ! jq -e '.success == true and ((.errors // []) | length == 0)' >/dev/null <<<"${response}"; then
  printf 'Échec de l’import du dashboard Kibana :\n%s\n' "${response}" >&2
  exit 1
fi

printf 'Dashboard Kibana importé ou mis à jour : %s objet(s).\n' \
  "$(jq -r '.successCount // 0' <<<"${response}")"
