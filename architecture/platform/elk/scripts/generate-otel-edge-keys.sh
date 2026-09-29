#!/usr/bin/env bash
# À charger, ne pas exécuter : source ./platform/elk/scripts/generate-otel-edge-keys.sh
# Les clés et identifiants restent dans un fichier local ignoré par Git et dans
# l'environnement du shell courant.

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  printf 'Utilisation : source %s\n' "$0" >&2
  exit 1
fi

_otel_edge_keys_fail() {
  printf 'generate-otel-edge-keys: %s\n' "$1" >&2
  return 1
}

command -v openssl >/dev/null 2>&1 || {
  _otel_edge_keys_fail 'openssl est requis.'
  return 1
}

_otel_edge_keys_file="${OTEL_EDGE_KEYS_FILE:-.otel-edge-keys.env}"

if [[ -f "${_otel_edge_keys_file}" && "${OTEL_EDGE_KEYS_ROTATE:-0}" != '1' ]]; then
  # shellcheck disable=SC1090
  source "${_otel_edge_keys_file}" || {
    _otel_edge_keys_fail "impossible de charger ${_otel_edge_keys_file}."
    return 1
  }
else
  _otel_edge_keys_directory="$(dirname "${_otel_edge_keys_file}")"
  mkdir -p "${_otel_edge_keys_directory}" || {
    _otel_edge_keys_fail "impossible de créer ${_otel_edge_keys_directory}."
    return 1
  }
  _otel_edge_keys_tmp="$(mktemp "${_otel_edge_keys_file}.tmp.XXXXXX")" || {
    _otel_edge_keys_fail "impossible de créer le fichier temporaire."
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
  } >"${_otel_edge_keys_tmp}" || {
    rm -f "${_otel_edge_keys_tmp}"
    _otel_edge_keys_fail 'impossible d’écrire les clés générées.'
    return 1
  }
  chmod 600 "${_otel_edge_keys_tmp}"
  mv -f "${_otel_edge_keys_tmp}" "${_otel_edge_keys_file}" || {
    rm -f "${_otel_edge_keys_tmp}"
    _otel_edge_keys_fail "impossible d'installer ${_otel_edge_keys_file}."
    return 1
  }
  # shellcheck disable=SC1090
  source "${_otel_edge_keys_file}" || {
    _otel_edge_keys_fail "impossible de charger ${_otel_edge_keys_file}."
    return 1
  }
  printf 'Cinq clés OTLP Edge générées dans %s.\n' "${_otel_edge_keys_file}"
fi

# Compléter un ancien fichier de clés qui ne contenait pas encore les
# identifiants Kafka OTel. Les valeurs sont ajoutées sans jamais être affichées.
if [[ -z "${KAFKA_OTEL_PUBLISHER_PASSWORD:-}" || -z "${KAFKA_OTEL_CONSUMER_PASSWORD:-}" ]]; then
  umask 077
  {
    [[ -n "${KAFKA_OTEL_PUBLISHER_PASSWORD:-}" ]] ||
      printf 'export KAFKA_OTEL_PUBLISHER_PASSWORD=%q\n' "$(openssl rand -hex 32)"
    [[ -n "${KAFKA_OTEL_CONSUMER_PASSWORD:-}" ]] ||
      printf 'export KAFKA_OTEL_CONSUMER_PASSWORD=%q\n' "$(openssl rand -hex 32)"
  } >>"${_otel_edge_keys_file}" || {
    _otel_edge_keys_fail "impossible d'ajouter les identifiants Kafka à ${_otel_edge_keys_file}."
    return 1
  }
  # shellcheck disable=SC1090
  source "${_otel_edge_keys_file}" || {
    _otel_edge_keys_fail "impossible de recharger ${_otel_edge_keys_file}."
    return 1
  }
fi

export OTEL_EDGE_KEY_KUBERNETES OTEL_EDGE_KEY_KUBERNETES_CLUSTER
export OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE OTEL_EDGE_KEY_EDGE_AGENT
export OTEL_EDGE_KEY_ELK_AGENT
export KAFKA_OTEL_PUBLISHER_PASSWORD KAFKA_OTEL_CONSUMER_PASSWORD

[[ -n "${OTEL_EDGE_KEY_KUBERNETES:-}" ]] || {
  _otel_edge_keys_fail 'OTEL_EDGE_KEY_KUBERNETES est absente du fichier de clés.'
  return 1
}
[[ -n "${OTEL_EDGE_KEY_KUBERNETES_CLUSTER:-}" ]] || {
  _otel_edge_keys_fail 'OTEL_EDGE_KEY_KUBERNETES_CLUSTER est absente du fichier de clés.'
  return 1
}
[[ -n "${OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE:-}" ]] || {
  _otel_edge_keys_fail 'OTEL_EDGE_KEY_SUPERMARKET_MIDDLEWARE est absente du fichier de clés.'
  return 1
}
[[ -n "${OTEL_EDGE_KEY_EDGE_AGENT:-}" ]] || {
  _otel_edge_keys_fail 'OTEL_EDGE_KEY_EDGE_AGENT est absente du fichier de clés.'
  return 1
}
[[ -n "${OTEL_EDGE_KEY_ELK_AGENT:-}" ]] || {
  _otel_edge_keys_fail 'OTEL_EDGE_KEY_ELK_AGENT est absente du fichier de clés.'
  return 1
}
[[ -n "${KAFKA_OTEL_PUBLISHER_PASSWORD:-}" ]] || {
  _otel_edge_keys_fail 'KAFKA_OTEL_PUBLISHER_PASSWORD est absente du fichier de clés.'
  return 1
}
[[ -n "${KAFKA_OTEL_CONSUMER_PASSWORD:-}" ]] || {
  _otel_edge_keys_fail 'KAFKA_OTEL_CONSUMER_PASSWORD est absente du fichier de clés.'
  return 1
}

printf 'Clés OTLP Edge et identifiants Kafka OTel disponibles dans le shell courant.\n'

unset _otel_edge_keys_file _otel_edge_keys_directory _otel_edge_keys_tmp
