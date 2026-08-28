#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  create-namespace-java-agent.sh <namespace>

Variables facultatives:
  ELASTIC_AGENT_VERSION   Version de l'image Elastic Agent (défaut: 8.11.3)
  ELASTIC_AGENT_NAME      Nom de la ressource Agent (défaut: java-metrics)
  ELASTICSEARCH_HOST      URL Elasticsearch (défaut: https://elasticsearch.elastic-system.svc:9200)
  ELASTICSEARCH_SECRET    Secret contenant ELASTICSEARCH_API_KEY (optionnel)
  LOGSTASH_HOST           Adresse Logstash:port; prioritaire sur Elasticsearch
  DATASET                 Dataset métriques (défaut: app.prometheus.java)
  DATA_STREAM_NAMESPACE   Namespace du data stream (défaut: homologation)

Annotations attendues sur les Services:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"       (optionnel, premier port sinon)
  prometheus.io/path: /actuator/prometheus (optionnel)
EOF
}

[[ $# -eq 1 ]] || { usage >&2; exit 64; }

namespace=$1
agent_version=${ELASTIC_AGENT_VERSION:-8.11.3}
agent_name=${ELASTIC_AGENT_NAME:-java-metrics}
elasticsearch_host=${ELASTICSEARCH_HOST:-https://elasticsearch.elastic-system.svc:9200}
dataset=${DATASET:-app.prometheus.java}
stream_namespace=${DATA_STREAM_NAMESPACE:-homologation}

command -v kubectl >/dev/null || { echo "kubectl est requis" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq est requis" >&2; exit 1; }

kubectl get namespace "$namespace" >/dev/null

echo "Services du namespace ${namespace}:"
kubectl -n "$namespace" get services -o wide

services_json=$(kubectl -n "$namespace" get services -o json)
services=()
while IFS= read -r service; do
  services+=("$service")
done < <(
  jq -r '.items[]
    | select(.metadata.annotations["prometheus.io/scrape"] == "true")
    | .metadata.name' <<<"$services_json"
)

if ((${#services[@]} == 0)); then
  echo "Aucun Service annoté prometheus.io/scrape=true dans ${namespace}." >&2
  echo "Le script ne crée pas d'Agent sans cible explicite." >&2
  exit 2
fi

echo
echo "Services retenus pour le scrape: ${services[*]}"

streams=''
for service in "${services[@]}"; do
  service_json=$(jq -c --arg name "$service" '.items[] | select(.metadata.name == $name)' <<<"$services_json")
  port=$(jq -r '
    (.metadata.annotations["prometheus.io/port"] // "") as $annotated
    | if $annotated != "" then $annotated
      else (.spec.ports[] | select(.name == "http" or .name == "prometheus") | .port | tostring) // (.spec.ports[0].port | tostring)
      end' <<<"$service_json" | head -n 1)
  path=$(jq -r '.metadata.annotations["prometheus.io/path"] // "/actuator/prometheus"' <<<"$service_json")

  [[ "$port" =~ ^[0-9]+$ ]] || {
    echo "Port introuvable pour le Service ${service}" >&2
    exit 3
  }

  streams+=$(cat <<EOF
          - id: ${service}
            data_stream:
              type: metrics
              dataset: ${dataset}
              namespace: ${stream_namespace}
            metricsets: [collector]
            hosts: ["http://${service}.${namespace}.svc:${port}"]
            metrics_path: ${path}
            period: 15s
            processors:
              - add_fields:
                  target: service
                  fields:
                    name: ${service}
                    environment: ${stream_namespace}
EOF
)
done

if [[ -n "${LOGSTASH_HOST:-}" ]]; then
  output=$(cat <<EOF
      default:
        type: logstash
        hosts: ["${LOGSTASH_HOST}"]
EOF
)
else
  [[ -n "${ELASTICSEARCH_SECRET:-}" ]] || {
    echo "Définir LOGSTASH_HOST ou ELASTICSEARCH_SECRET avant de créer l'Agent." >&2
    exit 4
  }
  output=$(cat <<EOF
      default:
        type: elasticsearch
        hosts: ["${elasticsearch_host}"]
        api_key: "\${ELASTICSEARCH_API_KEY}"
EOF
)
fi

pod_env=''
if [[ -z "${LOGSTASH_HOST:-}" ]]; then
  pod_env=$(cat <<EOF
            env:
              - name: ELASTICSEARCH_API_KEY
                valueFrom:
                  secretKeyRef:
                    name: ${ELASTICSEARCH_SECRET}
                    key: ELASTICSEARCH_API_KEY
EOF
)
fi

cat <<EOF | kubectl apply -f -
apiVersion: agent.k8s.elastic.co/v1alpha1
kind: Agent
metadata:
  name: ${agent_name}
  namespace: ${namespace}
spec:
  version: ${agent_version}
  mode: standalone
  deployment:
    replicas: 1
    podTemplate:
      spec:
        containers:
          - name: agent
${pod_env}
            resources:
              requests:
                cpu: 50m
                memory: 128Mi
              limits:
                cpu: 250m
                memory: 256Mi
  config:
    outputs:
${output}
    inputs:
      - id: java-applications-prometheus
        type: prometheus/metrics
        use_output: default
        streams:
${streams}
EOF

echo "Agent ${agent_name} appliqué dans le namespace ${namespace}."
echo "Vérification: kubectl -n ${namespace} get agent,deployments"
