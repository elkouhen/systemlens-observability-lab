#!/usr/bin/env bash
# Supprime le dashboard MongoDB retiré et ses objets sauvegardés dédiés.
set -euo pipefail

kibana_url="${KIBANA_URL:-https://kibana.poc.test}"
kibana_user="${KIBANA_USERNAME:-elastic}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.poc.test:443:127.0.0.1}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant de supprimer les objets Kibana}"

delete_object() {
  local object_type="$1"
  local object_id="$2"
  local response

  response="$(curl --silent --show-error --insecure \
    --resolve "${kibana_resolve}" \
    -u "${kibana_user}:${KIBANA_PASSWORD}" \
    -H 'kbn-xsrf: systemlens-dashboard-delete' \
    -o /dev/null -w '%{http_code}' \
    -X DELETE "${kibana_url}/api/saved_objects/${object_type}/${object_id}?force=true")"

  case "${response}" in
    200|404) ;;
    *)
      printf 'Échec de la suppression de %s/%s (HTTP %s).\n' \
        "${object_type}" "${object_id}" "${response}" >&2
      exit 1
      ;;
  esac
}

delete_object dashboard systemlens-mongodb-cluster-primary-overview
delete_object visualization systemlens-mongodb-clusters-and-primaries
delete_object index-pattern systemlens-mongodb-replstatus

printf 'Objets sauvegardés du dashboard MongoDB supprimé.\n'
