#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  collect-namespace-kafka-metrics.sh <namespace> [fichier-sortie]

Le script inspecte chaque pod en fonctionnement du namespace et appelle,
depuis le pod lui-même:

  http://localhost:8080/actuator/prometheus

Seules les lignes contenant "linger" ou "batch" sont conservées.
EOF
}

[[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 64; }

namespace=$1
output_file=${2:-"kafka-metrics-${namespace}.log"}

command -v kubectl >/dev/null || {
  echo "kubectl est requis" >&2
  exit 1
}

kubectl get namespace "$namespace" >/dev/null

{
  echo "# Collecte des métriques Kafka applicatives"
  echo "# Namespace: ${namespace}"
  echo "# Endpoint: http://localhost:8080/actuator/prometheus"
  echo "# Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
} >"$output_file"

pod_count=0
while read -r pod phase _; do
  [[ -n "${pod:-}" ]] || continue
  pod_count=$((pod_count + 1))

  {
    echo "### ${pod}"
    echo "status: ${phase}"
  } >>"$output_file"

  if [[ "$phase" != "Running" ]]; then
    echo "collecte: pod non actif, endpoint non interrogé" >>"$output_file"
    echo >>"$output_file"
    continue
  fi

  metrics=$(kubectl exec -n "$namespace" "$pod" -- sh -c '
    if command -v curl >/dev/null 2>&1; then
      curl --fail --silent --show-error http://localhost:8080/actuator/prometheus
    elif command -v wget >/dev/null 2>&1; then
      wget -qO- http://localhost:8080/actuator/prometheus
    else
      echo "outil HTTP absent: curl ou wget requis" >&2
      exit 127
    fi
  ' 2>&1) || {
    {
      echo "collecte: échec"
      echo "$metrics"
      echo
    } >>"$output_file"
    echo "Échec de collecte pour ${pod}" >&2
    continue
  }

  filtered_metrics=$(printf '%s\n' "$metrics" | grep -Ei 'linger|batch' || true)
  if [[ -n "$filtered_metrics" ]]; then
    {
      echo "collecte: succès"
      printf '%s\n' "$filtered_metrics"
    } >>"$output_file"
  else
    echo "collecte: aucune ligne contenant linger ou batch" >>"$output_file"
  fi
  echo >>"$output_file"
done < <(kubectl -n "$namespace" get pods \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' --no-headers)

if ((pod_count == 0)); then
  echo "Aucun pod trouvé dans ${namespace}." >&2
  exit 2
fi

echo "${pod_count} pod(s) inspecté(s). Résultat: ${output_file}"
