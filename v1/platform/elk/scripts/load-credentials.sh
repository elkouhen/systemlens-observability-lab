#!/usr/bin/env bash
# À charger, ne pas exécuter : source ./platform/elk/scripts/load-credentials.sh
# Les secrets restent uniquement dans l'environnement du shell courant.

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  printf 'Utilisation : source %s\n' "$0" >&2
  exit 1
fi

_credentials_fail() {
  printf 'load-credentials: %s\n' "$1" >&2
  return 1
}

command -v kubectl >/dev/null 2>&1 || {
  _credentials_fail 'kubectl est requis.'
  return 1
}
command -v curl >/dev/null 2>&1 || {
  _credentials_fail 'curl est requis.'
  return 1
}
command -v jq >/dev/null 2>&1 || {
  _credentials_fail 'jq est requis.'
  return 1
}

export ELASTICSEARCH_URL="${ELASTICSEARCH_URL:-https://elasticsearch.poc.test:443}"
export KIBANA_URL="${KIBANA_URL:-https://kibana.poc.test}"
_credentials_namespace="${ELASTIC_NAMESPACE:-elastic-stack}"
_credentials_app_namespace="${APP_NAMESPACE:-h0tl-supermarche-app}"
_credentials_resolve="${ELASTICSEARCH_CURL_RESOLVE:-elasticsearch.poc.test:443:127.0.0.1}"

# Le Secret applicatif est la source persistante du mot de passe PostgreSQL.
# Une valeur déjà fournie par un coffre-fort reste prioritaire ; le Secret est
# utilisé pour permettre à `source` puis `make deploy` de fonctionner sans
# recopier le mot de passe dans le shell.
if [[ -z "${POSTGRESQL_PASSWORD:-}" ]]; then
  POSTGRESQL_PASSWORD="$(kubectl -n "${_credentials_app_namespace}" get secret postgresql-credentials \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode)" || {
      _credentials_fail 'impossible de lire le secret postgresql-credentials.'
      return 1
    }
  [[ -n "${POSTGRESQL_PASSWORD}" ]] || {
    _credentials_fail 'le secret postgresql-credentials ne contient pas de mot de passe.'
    return 1
  }
  export POSTGRESQL_PASSWORD
fi

ELASTICSEARCH_PASSWORD="$(kubectl -n "${_credentials_namespace}" get secret elasticsearch-es-elastic-user \
  -o jsonpath='{.data.elastic}' | base64 --decode)" || {
  _credentials_fail 'impossible de lire le secret elasticsearch-es-elastic-user.'
  return 1
}
export ELASTICSEARCH_PASSWORD
export KIBANA_PASSWORD="${KIBANA_PASSWORD:-${ELASTICSEARCH_PASSWORD}}"

APM_SECRET_TOKEN="$(kubectl -n "${_credentials_namespace}" get secret apm-server-apm-token \
  -o jsonpath='{.data.secret-token}' | base64 --decode)" || {
  _credentials_fail 'impossible de lire le secret apm-server-apm-token.'
  return 1
}
export APM_SECRET_TOKEN

# Une clé déjà chargée (par exemple depuis un coffre-fort) n'est jamais
# remplacée. Sinon une nouvelle clé limitée aux data streams Beats est créée.
if [[ -z "${ELASTICSEARCH_API_KEY:-}" ]]; then
  _credentials_payload='{"name":"vm-beats-shell","role_descriptors":{"vm_beats_writer":{"cluster":["monitor","read_ilm","manage_ilm","manage_index_templates"],"indices":[{"names":["logs-*","metrics-*","filebeat-*","metricbeat-*"],"privileges":["auto_configure","create_doc","view_index_metadata"]}]}}}'
  ELASTICSEARCH_API_KEY="$(curl --fail --silent --show-error --insecure \
    --resolve "${_credentials_resolve}" \
    -u "elastic:${ELASTICSEARCH_PASSWORD}" \
    -H 'Content-Type: application/json' \
    -X POST "${ELASTICSEARCH_URL}/_security/api_key" \
    --data "${_credentials_payload}" | jq -er '.id + ":" + .api_key')" || {
      _credentials_fail 'impossible de créer la clé API Elasticsearch.'
      return 1
    }
  export ELASTICSEARCH_API_KEY
fi

printf 'Identifiants chargés : ELASTICSEARCH_PASSWORD, KIBANA_PASSWORD, APM_SECRET_TOKEN, ELASTICSEARCH_API_KEY, POSTGRESQL_PASSWORD.\n'
unset _credentials_namespace _credentials_app_namespace _credentials_resolve _credentials_payload
