#!/usr/bin/env bash
# Journalise les réconciliations Kibana sans enregistrer d'identifiants.

dashboard_reconciliation_log="${DASHBOARD_RECONCILIATION_LOG:-${script_dir}/../dashboards/reconciliation-history.md}"

record_dashboard_reconciliation() {
  local dashboard_id="$1"
  local operation="$2"
  local result="${3:-OK}"
  local timestamp
  operation="${operation//|/\\|}"
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '| %s | `%s` | `%s` | `%s` |\n' \
    "${timestamp}" "${dashboard_id}" "${operation}" "${result}" >>"${dashboard_reconciliation_log}"
}
