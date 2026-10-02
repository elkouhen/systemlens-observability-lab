#!/usr/bin/env bash
# À charger, ne pas exécuter : source ./platform/elk/scripts/generate-otel-edge-keys.sh
# Les identifiants restent dans un fichier local ignoré par Git et dans
# l'environnement du shell courant.

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  printf 'Utilisation : source %s\n' "$0" >&2
  exit 1
fi

_observability_credentials_fail() {
  printf 'generate-otel-edge-keys: %s\n' "$1" >&2
  return 1
}

command -v openssl >/dev/null 2>&1 || {
  _observability_credentials_fail 'openssl est requis.'
  return 1
}

_observability_credentials_file="${OBSERVABILITY_CREDENTIALS_FILE:-.observability-credentials.env}"
_observability_legacy_file="${OTEL_EDGE_KEYS_FILE:-.otel-edge-keys.env}"

# Migrer automatiquement l'ancien emplacement local s'il existe. Le fichier
# historique est ignoré par Git et peut encore contenir les clés du lab.
if [[ ! -f "${_observability_credentials_file}" && -f "${_observability_legacy_file}" ]]; then
  cp "${_observability_legacy_file}" "${_observability_credentials_file}" || {
    _observability_credentials_fail "impossible de migrer ${_observability_legacy_file}."
    return 1
  }
  chmod 600 "${_observability_credentials_file}"
fi

if [[ -f "${_observability_credentials_file}" && "${OBSERVABILITY_CREDENTIALS_ROTATE:-${OTEL_EDGE_KEYS_ROTATE:-0}}" != '1' ]]; then
  # shellcheck disable=SC1090
  source "${_observability_credentials_file}" || {
    _observability_credentials_fail "impossible de charger ${_observability_credentials_file}."
    return 1
  }
else
  _observability_credentials_directory="$(dirname "${_observability_credentials_file}")"
  mkdir -p "${_observability_credentials_directory}" || {
    _observability_credentials_fail "impossible de créer ${_observability_credentials_directory}."
    return 1
  }
  _observability_credentials_tmp="$(mktemp "${_observability_credentials_file}.tmp.XXXXXX")" || {
    _observability_credentials_fail "impossible de créer le fichier temporaire."
    return 1
  }
  umask 077
  {
    printf 'export OTEL_EDGE_KEY_KUBERNETES=%q\n' "$(openssl rand -hex 32)"
    printf 'export OTEL_EDGE_KEY_KUBERNETES_CLUSTER=%q\n' "$(openssl rand -hex 32)"
    printf 'export OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE=%q\n' "$(openssl rand -hex 32)"
    printf 'export OTEL_EDGE_KEY_EDGE_AGENT=%q\n' "$(openssl rand -hex 32)"
    printf 'export OTEL_EDGE_KEY_ELK_AGENT=%q\n' "$(openssl rand -hex 32)"
    printf 'export KAFKA_OTEL_PUBLISHER_PASSWORD=%q\n' "$(openssl rand -hex 32)"
    printf 'export KAFKA_OTEL_CONSUMER_PASSWORD=%q\n' "$(openssl rand -hex 32)"
    printf 'export POSTGRESQL_PASSWORD=%q\n' "$(openssl rand -hex 32)"
    printf 'export MONGODB_PASSWORD=%q\n' "$(openssl rand -hex 32)"
    printf 'export ELASTIC_PASSWORD=%q\n' "$(openssl rand -hex 32)"
  } >"${_observability_credentials_tmp}" || {
    rm -f "${_observability_credentials_tmp}"
    _observability_credentials_fail 'impossible d’écrire les identifiants générés.'
    return 1
  }
  chmod 600 "${_observability_credentials_tmp}"
  mv -f "${_observability_credentials_tmp}" "${_observability_credentials_file}" || {
    rm -f "${_observability_credentials_tmp}"
    _observability_credentials_fail "impossible d'installer ${_observability_credentials_file}."
    return 1
  }
  # shellcheck disable=SC1090
  source "${_observability_credentials_file}" || {
    _observability_credentials_fail "impossible de charger ${_observability_credentials_file}."
    return 1
  }
  printf 'Identifiants d’observabilité générés dans %s.\n' "${_observability_credentials_file}"
fi

# Compléter un fichier existant avec les identifiants ajoutés au périmètre.
# Les valeurs sont ajoutées sans jamais être affichées.
if [[ -z "${KAFKA_OTEL_PUBLISHER_PASSWORD:-}" || -z "${KAFKA_OTEL_CONSUMER_PASSWORD:-}" || -z "${POSTGRESQL_PASSWORD:-}" || -z "${MONGODB_PASSWORD:-}" || -z "${ELASTIC_PASSWORD:-}" ]]; then
  umask 077
  {
    [[ -n "${KAFKA_OTEL_PUBLISHER_PASSWORD:-}" ]] ||
      printf 'export KAFKA_OTEL_PUBLISHER_PASSWORD=%q\n' "$(openssl rand -hex 32)"
    [[ -n "${KAFKA_OTEL_CONSUMER_PASSWORD:-}" ]] ||
      printf 'export KAFKA_OTEL_CONSUMER_PASSWORD=%q\n' "$(openssl rand -hex 32)"
    [[ -n "${POSTGRESQL_PASSWORD:-}" ]] ||
      printf 'export POSTGRESQL_PASSWORD=%q\n' "$(openssl rand -hex 32)"
    [[ -n "${MONGODB_PASSWORD:-}" ]] ||
      printf 'export MONGODB_PASSWORD=%q\n' "$(openssl rand -hex 32)"
    [[ -n "${ELASTIC_PASSWORD:-}" ]] ||
      printf 'export ELASTIC_PASSWORD=%q\n' "$(openssl rand -hex 32)"
  } >>"${_observability_credentials_file}" || {
    _observability_credentials_fail "impossible d'ajouter les identifiants à ${_observability_credentials_file}."
    return 1
  }
  # shellcheck disable=SC1090
  source "${_observability_credentials_file}" || {
    _observability_credentials_fail "impossible de recharger ${_observability_credentials_file}."
    return 1
  }
fi

export OTEL_EDGE_KEY_KUBERNETES OTEL_EDGE_KEY_KUBERNETES_CLUSTER
export OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE OTEL_EDGE_KEY_EDGE_AGENT
export OTEL_EDGE_KEY_ELK_AGENT
export KAFKA_OTEL_PUBLISHER_PASSWORD KAFKA_OTEL_CONSUMER_PASSWORD
export POSTGRESQL_PASSWORD MONGODB_PASSWORD ELASTIC_PASSWORD

[[ -n "${OTEL_EDGE_KEY_KUBERNETES:-}" ]] || {
  _observability_credentials_fail 'OTEL_EDGE_KEY_KUBERNETES est absente du fichier d’identifiants.'
  return 1
}
[[ -n "${OTEL_EDGE_KEY_KUBERNETES_CLUSTER:-}" ]] || {
  _observability_credentials_fail 'OTEL_EDGE_KEY_KUBERNETES_CLUSTER est absente du fichier d’identifiants.'
  return 1
}
[[ -n "${OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE:-}" ]] || {
  _observability_credentials_fail 'OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE est absente du fichier d’identifiants.'
  return 1
}
[[ -n "${OTEL_EDGE_KEY_EDGE_AGENT:-}" ]] || {
  _observability_credentials_fail 'OTEL_EDGE_KEY_EDGE_AGENT est absente du fichier d’identifiants.'
  return 1
}
[[ -n "${OTEL_EDGE_KEY_ELK_AGENT:-}" ]] || {
  _observability_credentials_fail 'OTEL_EDGE_KEY_ELK_AGENT est absente du fichier d’identifiants.'
  return 1
}
[[ -n "${KAFKA_OTEL_PUBLISHER_PASSWORD:-}" ]] || {
  _observability_credentials_fail 'KAFKA_OTEL_PUBLISHER_PASSWORD est absente du fichier d’identifiants.'
  return 1
}
[[ -n "${KAFKA_OTEL_CONSUMER_PASSWORD:-}" ]] || {
  _observability_credentials_fail 'KAFKA_OTEL_CONSUMER_PASSWORD est absente du fichier d’identifiants.'
  return 1
}

for _observability_password in POSTGRESQL_PASSWORD MONGODB_PASSWORD ELASTIC_PASSWORD; do
  case "${_observability_password}" in
    POSTGRESQL_PASSWORD) _observability_password_value="${POSTGRESQL_PASSWORD:-}" ;;
    MONGODB_PASSWORD) _observability_password_value="${MONGODB_PASSWORD:-}" ;;
    ELASTIC_PASSWORD) _observability_password_value="${ELASTIC_PASSWORD:-}" ;;
  esac
  [[ -n "${_observability_password_value}" ]] || {
    _observability_credentials_fail "${_observability_password} est absent du fichier d’identifiants."
    return 1
  }
done

printf 'Identifiants d’observabilité disponibles dans le shell courant.\n'

unset _observability_credentials_file _observability_legacy_file
unset _observability_credentials_directory _observability_credentials_tmp
unset _observability_password _observability_password_value
