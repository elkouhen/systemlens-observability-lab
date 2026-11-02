# Briques de remontée de la télémétrie architecture

Ce document décrit la chaîne conservée de remontée des logs, traces et
métriques vers Elastic.

| Signal | Collecte | Transport | Destination |
| --- | --- | --- | --- |
| Traces applicatives | Agent Java OpenTelemetry | OTLP → Edge → Kafka `otel-traces` | Collector backend → APM Server |
| Logs applicatifs | Agent Java OpenTelemetry (Logback) | OTLP → Edge → Kafka `otel-logs` | Collector backend → Elasticsearch |
| Métriques applicatives | Micrometer OTLP | OTLP → Edge → Kafka `otel-metrics` | Collector backend → Elasticsearch |
| Métriques Kubernetes | EDOT DaemonSet `hostmetrics` | OTLP → Edge → Kafka `otel-metrics` | Collector backend → Elasticsearch |
| Logs et métriques VM | Elastic Agent en mode EDOT | OTLP → Edge → Kafka par signal | Collector backend → Elasticsearch |

Kafka absorbe les pics entre les producteurs et le Collector backend. Les
topics `otel-traces`, `otel-logs` et `otel-metrics`, et leurs déclinaisons
`-supermarche` (applications) et `-k8s` (collecteurs Kubernetes) choisies
par le collecteur Edge (ADR-009), sont consommés par le groupe
`otel-backend`. Le Collector applique le batch, la limitation mémoire
et la queue disque avant l'export Elasticsearch.

Les flux routés suivent la convention Elastic (ADR-010) : le dataset nomme
l'application, le namespace l'environnement. Les services `supermarket-demo`
écrivent dans `logs-supermarche.otel-homologation` (logs OTel natifs, ADR-012),
`metrics-supermarche.otel-homologation`,
`traces-apm-supermarche_homologation`,
`logs-apm.error-supermarche_homologation` et
`metrics-apm.<métrique>.1m-supermarche_homologation` : APM Server impose le
dataset `apm`, le namespace porte donc l'application et l'environnement. Les
collecteurs Kubernetes gardent le dataset
de leur receiver, par exemple `metrics-kubeletstatsreceiver.otel-homologation`.
Les signaux des VM restent dans le namespace `default`.

Les VM exécutent Elastic Agent en mode EDOT standalone. La configuration
locale collecte les logs système et les métriques hôte, puis exporte en OTLP
vers le Collecteur Edge. Les anciennes policies Fleet de collecte VM ne doivent
pas être actives en parallèle.

## Contrôles

```bash
kubectl -n elastic-stack get deployment,daemonset,pods
make otel-validation
make otel-gateway-vm-status
vagrant ssh supermarket-middleware-01 -c 'sudo /opt/Elastic/Agent/elastic-agent status'
```

## Sources IaC

- Collecteurs Kubernetes : [`otel-kafka.yaml`](../architecture/platform/kubernetes/base/observability/otel-kafka.yaml) ;
- instrumentation applicative : [`otel-instrumentation.yaml`](../kubernetes/apps/supermarket-demo/default/otel-instrumentation.yaml) ;
- configuration EDOT VM : [`elastic-agent.yml.j2`](../architecture/ansible/roles/elastic_agent/templates/elastic-agent.yml.j2) ;
- Collecteur Edge : [`otel-edge.yaml.j2`](../architecture/ansible/roles/otel_edge/templates/otel-edge.yaml.j2).
