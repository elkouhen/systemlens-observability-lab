# Briques de remontée de la télémétrie architecture

Ce document décrit la chaîne conservée de remontée des logs, traces et
métriques vers Elastic.

| Signal | Collecte | Transport | Destination |
| --- | --- | --- | --- |
| Traces applicatives | Agent Java OpenTelemetry | OTLP → Edge → Kafka `otel-traces` | Collector backend → APM Server |
| Logs applicatifs/Kubernetes | EDOT DaemonSet `filelog` | OTLP → Edge → Kafka `otel-logs` | Collector backend → Elasticsearch |
| Métriques applicatives | Micrometer OTLP | OTLP → Edge → Kafka `otel-metrics` | Collector backend → Elasticsearch |
| Métriques Kubernetes | EDOT DaemonSet `hostmetrics` | OTLP → Edge → Kafka `otel-metrics` | Collector backend → Elasticsearch |
| Logs et métriques VM | Elastic Agent en mode EDOT | OTLP → Edge → Kafka par signal | Collector backend → Elasticsearch |

Kafka absorbe les pics entre les producteurs et le Collector backend. Les
topics `otel-traces`, `otel-logs` et `otel-metrics` sont consommés par le
groupe `otel-backend`. Le Collector applique le batch, la limitation mémoire
et la queue disque avant l'export Elasticsearch.

Les VM exécutent Elastic Agent en mode EDOT standalone. La configuration
locale collecte les logs système et les métriques hôte, puis exporte en OTLP
vers le Collecteur Edge. Les anciennes policies Fleet de collecte VM ne doivent
pas être actives en parallèle.

## Contrôles

```bash
kubectl -n elastic-stack get deployment,daemonset,pods
make otel-validation
make otel-gateway-vm-status
vagrant ssh poc-01 -c 'sudo /opt/Elastic/Agent/elastic-agent status'
```

## Sources IaC

- Collecteurs Kubernetes : [`otel-kafka.yaml`](../architecture/platform/kubernetes/base/observability/otel-kafka.yaml) ;
- instrumentation applicative : [`otel-instrumentation.yaml`](../kubernetes/apps/supermarket-demo/default/otel-instrumentation.yaml) ;
- configuration EDOT VM : [`elastic-agent.yml.j2`](../architecture/ansible/roles/elastic_agent/templates/elastic-agent.yml.j2) ;
- Collecteur Edge : [`otel-edge.yaml.j2`](../architecture/ansible/roles/otel_edge/templates/otel-edge.yaml.j2).
