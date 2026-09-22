#!/usr/bin/env bash
# Réconciliation complète et lisible des dashboards OTel déployés dans Kibana.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant la réconciliation}"

run_step() {
  local label="$1"
  local script="$2"
  printf '\n==> %s\n' "${label}"
  "${script_dir}/${script}"
}

# Les étapes restent séparées pour garder des corrections ciblées et lisibles.
run_step 'Contrôles et filtres OTel (PostgreSQL et MongoDB)' \
  reconcile-otel-dashboard-controls.sh
run_step 'Requêtes ES|QL et configurations Lens PostgreSQL' \
  reconcile-otel-dashboard-queries.sh
run_step 'Libellés et descriptions PostgreSQL' \
  reconcile-otel-dashboard-labels.sh

printf '\nRéconciliation complète des dashboards OTel terminée.\n'
