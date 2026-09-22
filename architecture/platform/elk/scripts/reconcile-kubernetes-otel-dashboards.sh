#!/usr/bin/env bash
# Réconcilie les dashboards Kubernetes OTel installés par le package Fleet.
set -euo pipefail

command -v curl >/dev/null || { printf 'curl est requis.\n' >&2; exit 2; }
command -v jq >/dev/null || { printf 'jq est requis.\n' >&2; exit 2; }

kibana_url="${KIBANA_URL:-http://kibana.observability.test:5601}"
kibana_resolve="${KIBANA_CURL_RESOLVE:-kibana.observability.test:5601:192.168.33.30}"
: "${KIBANA_PASSWORD:?Définir KIBANA_PASSWORD avant la réconciliation des dashboards Kubernetes OTel}"

curl_args=(--fail --silent --show-error --insecure --resolve "${kibana_resolve}"
  -u "elastic:${KIBANA_PASSWORD}" -H 'kbn-xsrf: systemlens-kubernetes-otel-dashboards'
  -H 'Content-Type: application/json')

dashboard_list="$(curl "${curl_args[@]}" \
  "${kibana_url}/api/saved_objects/_find?type=dashboard&per_page=100&search_fields=title&search=Kubernetes%20OTel" \
  | jq '{saved_objects: [.saved_objects[] | select(.attributes.title | startswith("[Kubernetes OTel]"))]}')"

# Les dashboards Fleet embarquent leurs requêtes ES|QL dans panelsJSON. Les
# quatre champs ci-dessous appartiennent à une variante de schéma qui n'est
# pas produite par kubeletstats/k8s_cluster. Les expressions sont recalculées
# avec les champs bruts effectivement indexés par le Collector.
read -r -d '' jq_rewrite <<'JQ' || true
def rewrite_query:
  . as $q
  | if ($q | contains("last_terminated_reason")) then
      "FROM metrics-kubeletstatsreceiver.otel-*\n"
      + "| WHERE k8s.cluster.name IS NOT NULL AND k8s.cluster.name != \"\"\n"
      + "  AND k8s.namespace.name IS NOT NULL AND k8s.namespace.name != \"\"\n"
      + "  AND k8s.pod.uid IS NOT NULL\n"
      + "  AND k8s.container.name IS NOT NULL\n"
      + "  AND k8s.container.restarts IS NOT NULL\n"
      + "| STATS container_restarts = MAX(k8s.container.restarts)\n"
      + "  BY k8s.cluster.name, k8s.namespace.name, k8s.pod.uid, k8s.container.name, @timestamp = BUCKET(@timestamp, 50, ?_tstart, ?_tend)\n"
      + "| STATS `Container restarts` = SUM(container_restarts)\n"
      + "  BY k8s.cluster.name, k8s.namespace.name, @timestamp\n"
      + "| WHERE `Container restarts` > 0\n"
      + "| SORT @timestamp ASC, `Container restarts` DESC, k8s.namespace.name ASC\n"
      + "| LIMIT 10 BY @timestamp\n"
      + "| SORT @timestamp"
    elif ($q | contains("condition_memory_pressure")) and ($q | contains("memory_pressure = LAST")) then
      $q
      | gsub("memory_pressure = LAST\\(k8s\\.node\\.condition_memory_pressure, CASE\\(k8s\\.node\\.condition_memory_pressure IS NOT NULL, @timestamp, NULL\\)\\),";
          "memory_util = LAST(CASE(k8s.node.allocatable_memory > 0, TO_DOUBLE(k8s.node.memory.working_set) / TO_DOUBLE(k8s.node.allocatable_memory), NULL), CASE(k8s.node.memory.working_set IS NOT NULL AND k8s.node.allocatable_memory IS NOT NULL, @timestamp, NULL)),")
      | gsub("memory_pressure = MAX\\(memory_pressure\\),"; "memory_util = MAX(memory_util),")
      | gsub("mem_pressure = CASE\\(memory_pressure == 1, \\\"Memory pressure\\\", memory_pressure == 0, \\\"No memory pressure\\\", \\\"Unknown\\\"\\),";
          "mem_pressure = CASE(memory_util >= 0.9, \\\"High memory utilization\\\", memory_util IS NOT NULL, \\\"Normal memory utilization\\\", \\\"Unknown\\\"),")
    elif ($q | contains("condition_memory_pressure")) then
      $q
      | gsub("mem_press_val = MAX\\(k8s\\.node\\.condition_memory_pressure\\),"; "mem_used = AVG(k8s.node.memory.working_set),")
      | gsub("mem_pressure = CASE\\(\\n      mem_press_val == 0, \\\"No\\\",\\n      mem_press_val == 1, \\\"Yes\\\",\\n      \\\"Unknown\\\"\\),";
          "mem_pressure = CASE(\\n      alloc_mem > 0 AND TO_DOUBLE(mem_used) / TO_DOUBLE(alloc_mem) >= 0.9, \\\"High\\\",\\n      alloc_mem > 0, \\\"Normal\\\",\\n      \\\"Unknown\\\"\\),")
    elif ($q | contains("memory_limit_utilization")) then
      $q
      | gsub("k8s\\.pod\\.memory_limit_utilization"; "k8s.pod.memory_limit_utilization_REMOVED")
      | gsub("AND k8s\\.pod\\.memory_limit_utilization_REMOVED IS NOT NULL"; "AND (k8s.pod.memory.working_set IS NOT NULL OR k8s.container.memory_limit IS NOT NULL)")
      | gsub("mem_limit_util = AVG\\(k8s\\.pod\\.memory_limit_utilization_REMOVED\\),"; "mem_ws = AVG(k8s.pod.memory.working_set),\n    mem_limit = SUM(k8s.container.memory_limit),")
      | gsub("mem_limit_util = MAX\\(k8s\\.pod\\.memory_limit_utilization_REMOVED\\),"; "memory_limit = SUM(k8s.container.memory_limit),")
      | gsub("pod_util = MAX\\(k8s\\.pod\\.memory_limit_utilization_REMOVED\\)"; "pod_ws = MAX(k8s.pod.memory.working_set), pod_limit = SUM(k8s.container.memory_limit)")
      | gsub("`Memory limit utilization` = MAX\\(k8s\\.pod\\.memory_limit_utilization_REMOVED\\)"; "pod_ws = MAX(k8s.pod.memory.working_set), pod_limit = SUM(k8s.container.memory_limit)")
      | gsub("\\| STATS bucket_util = AVG\\(pod_util\\)"; "| EVAL pod_util = CASE(pod_limit > 0, TO_DOUBLE(pod_ws) / TO_DOUBLE(pod_limit), NULL)\n| WHERE pod_util IS NOT NULL\n| STATS bucket_util = AVG(pod_util)")
      | gsub("\\| EVAL restarts = COALESCE\\(restarts, 0\\)"; "| EVAL mem_limit_util = CASE(mem_limit > 0, TO_DOUBLE(mem_ws) / TO_DOUBLE(mem_limit), NULL),\n    restarts = COALESCE(restarts, 0)")
      | gsub("    restarts = COALESCE\\(restarts, 0\\)"; "    mem_limit_util = CASE(memory_limit > 0, TO_DOUBLE(memory_ws) / TO_DOUBLE(memory_limit), NULL),\n    restarts = COALESCE(restarts, 0)")
      | gsub("\\| SORT timestamp\n\\| KEEP timestamp, k8s\\.cluster\\.name, k8s\\.namespace\\.name, k8s\\.deployment\\.name, k8s\\.pod\\.name, `Memory limit utilization`"; "| EVAL `Memory limit utilization` = CASE(pod_limit > 0, TO_DOUBLE(pod_ws) / TO_DOUBLE(pod_limit), NULL)\n| SORT timestamp\n| KEEP timestamp, k8s.cluster.name, k8s.namespace.name, k8s.deployment.name, k8s.pod.name, `Memory limit utilization`")
      | gsub("\\| STATS\\n    utilization = ROUND\\(AVG\\(k8s\\.pod\\.memory_limit_utilization_REMOVED\\), 4\\),\\n    utilization_last = ROUND\\(LAST\\(k8s\\.pod\\.memory_limit_utilization_REMOVED, @timestamp\\), 4\\)"; "| STATS pod_ws = MAX(k8s.pod.memory.working_set), pod_limit = SUM(k8s.container.memory_limit)\n| EVAL utilization = CASE(pod_limit > 0, ROUND(TO_DOUBLE(pod_ws) / TO_DOUBLE(pod_limit), 4), NULL), utilization_last = utilization")
    elif ($q | contains("cpu_limit_utilization")) then
      $q
      | gsub("k8s\\.pod\\.cpu_limit_utilization"; "k8s.pod.cpu_limit_utilization_REMOVED")
      | gsub("AND k8s\\.pod\\.cpu_limit_utilization_REMOVED IS NOT NULL"; "AND (k8s.pod.cpu.usage IS NOT NULL OR k8s.container.cpu_limit IS NOT NULL)")
      | gsub("pod_util = MAX\\(k8s\\.pod\\.cpu_limit_utilization_REMOVED\\)"; "pod_usage = MAX(k8s.pod.cpu.usage), pod_limit = SUM(k8s.container.cpu_limit)")
      | gsub("`CPU limit utilization` = MAX\\(k8s\\.pod\\.cpu_limit_utilization_REMOVED\\)"; "pod_usage = MAX(k8s.pod.cpu.usage), pod_limit = SUM(k8s.container.cpu_limit)")
      | gsub("\\| STATS bucket_util = AVG\\(pod_util\\)"; "| EVAL pod_util = CASE(pod_limit > 0, TO_DOUBLE(pod_usage) / TO_DOUBLE(pod_limit), NULL)\n| WHERE pod_util IS NOT NULL\n| STATS bucket_util = AVG(pod_util)")
      | gsub("\\| SORT timestamp\n\\| KEEP timestamp, k8s\\.cluster\\.name, k8s\\.namespace\\.name, k8s\\.deployment\\.name, k8s\\.pod\\.name, `CPU limit utilization`"; "| EVAL `CPU limit utilization` = CASE(pod_limit > 0, TO_DOUBLE(pod_usage) / TO_DOUBLE(pod_limit), NULL)\n| SORT timestamp\n| KEEP timestamp, k8s.cluster.name, k8s.namespace.name, k8s.deployment.name, k8s.pod.name, `CPU limit utilization`")
      | gsub("\\| STATS bucket_util = AVG\\(k8s\\.pod\\.cpu_limit_utilization_REMOVED\\)"; "| STATS pod_usage = MAX(k8s.pod.cpu.usage), pod_limit = SUM(k8s.container.cpu_limit)\n  BY timestamp = BUCKET(@timestamp, 50, ?_tstart, ?_tend)\n| EVAL bucket_util = CASE(pod_limit > 0, TO_DOUBLE(pod_usage) / TO_DOUBLE(pod_limit), NULL)\n| WHERE bucket_util IS NOT NULL")
    else $q end;

def rewrite_panel:
  . as $panel
  | ($panel.embeddableConfig.attributes.state.query.esql? // null) as $query
  | if ($query | type) == "string" then
      ($query | rewrite_query) as $rewritten
      | .embeddableConfig.attributes.state.query.esql = $rewritten
      | if ($query | contains("last_terminated_reason")) then
        .embeddableConfig.attributes.title |= gsub("OOMKilled"; "Container restarts")
          | .embeddableConfig.attributes.description? |= if type == "string" then gsub("OOMKilled"; "container restarts") else . end
        elif ($query | contains("condition_memory_pressure")) then
          .embeddableConfig.attributes.title |= gsub("Memory pressure"; "Memory utilization")
          | .embeddableConfig.attributes.description? |= if type == "string" then gsub("Memory pressure"; "Memory utilization") else . end
        else . end
    else . end;

map(rewrite_panel)
JQ

patch_dashboard() {
  local id="$1" title="$2" object panels patched_panels patched_payload
  object="$(curl "${curl_args[@]}" "${kibana_url}/api/saved_objects/dashboard/${id}")"
  # panelsJSON est une chaîne JSON dans l'objet sauvegardé.
  panels="$(jq -c '.attributes.panelsJSON | fromjson' <<<"${object}")"
  patched_panels="$(jq -c "${jq_rewrite}" <<<"${panels}")"
  patched_payload="$(jq --arg panels_json "${patched_panels}" \
    '.attributes.panelsJSON = $panels_json | {attributes: .attributes}' <<<"${object}")"
  if [[ "$(jq -c . <<<"${panels}")" == "$(jq -c . <<<"${patched_panels}")" ]]; then
    printf 'OK      %s (déjà conforme)\n' "${title}"
    return 0
  fi
  curl "${curl_args[@]}" -X PUT "${kibana_url}/api/saved_objects/dashboard/${id}" \
    --data "${patched_payload}" >/dev/null
  printf 'CORRIGE %s\n' "${title}"
}

count=0
while IFS=$'\t' read -r id title; do
  [[ -n "${id}" ]] || continue
  patch_dashboard "${id}" "${title}"
  count=$((count + 1))
done < <(jq -r '.saved_objects[] | [.id, .attributes.title] | @tsv' <<<"${dashboard_list}")

(( count == 11 )) || { printf 'Nombre inattendu de dashboards Kubernetes OTel : %s (attendu 11).\n' "${count}" >&2; exit 1; }
printf '%s dashboards Kubernetes OTel réconciliés.\n' "${count}"
