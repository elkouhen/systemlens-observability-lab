# Briques de remontée de la télémétrie architecture

Ce document décrit la chaîne conservée de remontée des logs, traces et
métriques vers Elastic.

| Signal | Collecte | Transport | Destination |
| --- | --- | --- | --- |
| Traces applicatives | Agent Java OpenTelemetry | OTLP → Gateway → Kafka `otel-traces` | Collector backend → Elasticsearch |
| Logs applicatifs/Kubernetes | EDOT DaemonSet `filelog` | Kafka `otel-logs` | Collector backend → Elasticsearch |
| Métriques applicatives | Receiver Prometheus du Gateway sur `/actuator/prometheus` | Kafka `otel-metrics` | Collector backend → Elasticsearch |
| Métriques Kubernetes | EDOT DaemonSet `hostmetrics` | Kafka `otel-metrics` | Collector backend → Elasticsearch |
| Logs et métriques VM | Elastic Agent enrôlé dans Fleet | HTTPS direct | Elasticsearch |

Kafka absorbe les pics entre les producteurs et le Collector backend. Les
topics `otel-traces`, `otel-logs` et `otel-metrics` sont consommés par le
groupe `otel-backend`. Le Collector applique le batch, la limitation mémoire
et la queue disque avant l'export Elasticsearch.

Les VM sont enrôlées dans la policy Fleet `data-fleet`. Les intégrations
System, Kafka, MongoDB et PostgreSQL envoient directement leurs événements
vers Elasticsearch.

## Contrôles

```bash
kubectl -n elastic-stack get deployment,daemonset,pods
make kafka-jolokia-verify
make otel-validation
vagrant ssh poc-01 -c 'sudo systemctl is-active elastic-agent'
```

## Sources IaC

- Collecteurs Kubernetes : [`otel-kafka.yaml`](../architecture/platform/kubernetes/base/observability/otel-kafka.yaml) ;
- instrumentation applicative : [`otel-instrumentation.yaml`](../kubernetes/apps/supermarket-demo/default/otel-instrumentation.yaml) ;
- policy Fleet VM : [`bootstrap-fleet-policies.sh`](../architecture/platform/elk/scripts/bootstrap-fleet-policies.sh).
