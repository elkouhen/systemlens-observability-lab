#!/usr/bin/env bash
# Supprime puis réimporte un dashboard Kibana défini par l'API Dashboard.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dashboard_file="${1:?Usage : $0 <dashboard.json>}"
kibana_url="${KIBANA_URL:-https://kibana.observability.test}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:443:127.0.0.1}"

[[ -r "${dashboard_file}" ]] || { printf 'Fichier dashboard introuvable ou illisible : %s\n' "${dashboard_file}" >&2; exit 1; }
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de déployer le dashboard}"

dashboard_id="$(jq -er 'select(.panels | type == "array") | .id' "${dashboard_file}")" || {
  printf 'Le remplacement attend une définition JSON avec .id et .panels.\n' >&2
  exit 1
}

response_file="$(mktemp)"
trap 'rm -f "${response_file}"' EXIT
http_status="$(curl --silent --show-error --insecure --resolve "${kibana_resolve}" \
  -u "${kibana_user}:${KIBANA_PASSWORD}" -H 'kbn-xsrf: systemlens-dashboard-replace' \
  -X DELETE -o "${response_file}" -w '%{http_code}' \
  "${kibana_url}/api/dashboards/${dashboard_id}" || true)"

if [[ "${http_status}" != 200 && "${http_status}" != 204 && "${http_status}" != 404 ]]; then
  printf 'Échec de la suppression du dashboard %s (HTTP %s) :\n%s\n' "${dashboard_id}" "${http_status}" "$(<"${response_file}")" >&2
  exit 1
fi

printf 'Dashboard Kibana supprimé (ou déjà absent) : %s.\n' "${dashboard_id}"
exec "${script_dir}/deploy-kibana-dashboard.sh" "${dashboard_file}"
