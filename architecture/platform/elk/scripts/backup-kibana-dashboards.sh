#!/usr/bin/env bash
# Sauvegarde tous les dashboards Kibana et leurs objets référencés.
set -euo pipefail

: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant la sauvegarde}"

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:192.168.33.30}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backup_dir="${KIBANA_DASHBOARD_BACKUP_DIR:-${script_dir}/../dashboards/backups}"
mkdir -p "${backup_dir}"

curl_args=(
  --fail --silent --show-error --insecure
  --resolve "${kibana_resolve}"
  -u "${kibana_user}:${KIBANA_PASSWORD}"
)

tmp_export="$(mktemp)"
tmp_manifest="$(mktemp)"
trap 'rm -f "${tmp_export}" "${tmp_manifest}"' EXIT

curl "${curl_args[@]}" \
  -H 'kbn-xsrf: systemlens-dashboard-backup' \
  -H 'Content-Type: application/json' \
  -X POST "${kibana_url}/api/saved_objects/_export" \
  --data '{"type":["dashboard"],"includeReferencesDeep":true,"excludeExportDetails":false}' \
  -o "${tmp_export}"

test -s "${tmp_export}" || { echo 'Export Kibana vide.' >&2; exit 1; }
jq -e 'select(.type == "dashboard")' "${tmp_export}" >/dev/null

exported_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
sha256="$(shasum -a 256 "${tmp_export}" | awk '{print $1}')"
jq -s \
  --arg exported_at "${exported_at}" \
  --arg sha256 "${sha256}" \
  --arg kibana_url "${kibana_url}" \
  '{schema_version:1, exported_at:$exported_at, source:{kibana_url:$kibana_url, api:"/api/saved_objects/_export", include_references_deep:true}, export_sha256:$sha256, dashboard_count:([.[] | select(.type == "dashboard")] | length), dashboards:[.[] | select(.type == "dashboard") | {id, title:.attributes.title, description:(.attributes.description // ""), references:([.references[]?.type] | unique | sort)}] | sort_by(.id)}' \
  "${tmp_export}" >"${tmp_manifest}"

mv "${tmp_export}" "${backup_dir}/kibana-dashboards.ndjson"
mv "${tmp_manifest}" "${backup_dir}/manifest.json"

printf 'Sauvegarde Kibana créée : %s\n' "${backup_dir}"
jq -r '"Dashboards sauvegardés : " + (.dashboard_count | tostring)' "${backup_dir}/manifest.json"
