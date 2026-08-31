# Différences entre les architectures v1 et v2

Ce document est la référence de comparaison entre les deux bundles
d'architecture. Il sera complété à chaque évolution de `v2`.

## Vue d'ensemble

| Sujet | v1 | v2 | État |
| --- | --- | --- | --- |
| Elastic/Kibana | Elastic Stack `8.11.3` | Elastic Stack `9.4.3` | Implémenté |
| Organisation | `v1/` contient la plateforme, Ansible et les manifests applicatifs | `v2/` contient sa propre plateforme, son Ansible et ses manifests applicatifs | Implémenté |
| Code Java, POM, Dockerfile | Partagé sous `apps/supermarket-demo/` | Partagé sous `apps/supermarket-demo/` | Inchangé |
| Makefile/Vagrantfile | Bundle `v1/` | Bundle `v2/` | Implémenté |
| Traces applicatives | Agent Elastic APM → APM Server → Logstash | OpenTelemetry Java Agent → Collector OTel → Kafka → Collector OTel → Elasticsearch OTLP | En cours v2 |
| Métriques applicatives/Kubernetes | Elastic Agent et pipelines Logstash | Collector OTel → Kafka → Elasticsearch OTLP | En cours v2 |
| Logs applicatifs/Kubernetes | Elastic Agent → Logstash | Collector OTel `filelog` → Kafka → Elasticsearch OTLP | En cours v2 |
| Stabilisation Kafka | Kafka transporte les événements métier et est observé par Fleet | Kafka transporte aussi les signaux OTel avec trois topics dédiés | En cours v2 |
| Versions OTel | Non utilisé pour les signaux du POC | Collector Contrib `0.153.0`, agent Java `2.28.1` | Implémenté v2 |
| VM `data-*` | Elastic Agent/Filebeat/Metricbeat selon le profil | Fleet conservé temporairement | À migrer |

## Contrat de transport v2

Les topics Kafka de télémétrie sont dédiés aux signaux et utilisent
l'encodage OTLP protobuf :

| Topic | Signal | Producteur | Consommateur |
| --- | --- | --- | --- |
| `otel-traces` | Traces | Collector OTel gateway | Collector OTel Elasticsearch |
| `otel-metrics` | Métriques | Collector OTel gateway/DaemonSet | Collector OTel Elasticsearch |
| `otel-logs` | Logs | Collector OTel DaemonSet | Collector OTel Elasticsearch |

Les topics sont créés par un Job Kubernetes idempotent. Le Collector de sortie
utilise un batch et une file d'attente locale éphémère ; la rétention et
la reprise après indisponibilité d'Elasticsearch sont d'abord assurées par
Kafka. La capacité, le nombre de partitions et la réplication devront être
mesurés avant un usage de production.

## Vérification prévue

```bash
make architecture-switch VERSION=v2
make kubernetes-validate
make elk-deploy
make apps-deploy
kubectl -n elastic-stack get deploy,daemonset,job otel-gateway otel-kafka-exporter otel-telemetry-topics
kubectl -n elastic-stack logs deployment/otel-kafka-exporter --tail=50
```

Résultat attendu : les trois topics existent, les Collectors sont prêts, et
les data streams `traces-*.otel-*`, `metrics-*.otel-*` et `logs-*.otel-*`
reçoivent les signaux de la démo.

## Décisions et points ouverts

- La v2 utilise l'endpoint OTLP/HTTP Elasticsearch ; Elasticsearch n'accepte
  pas OTLP/gRPC pour cette destination.
- Les logs sont collectés à partir de stdout Kubernetes par `filelog`; ils ne
  sont pas envoyés par le code Java.
- La migration des agents des VM vers OTel Collector doit être conçue dans
  `v2/ansible/` avant de retirer Fleet pour `data-01`, `data-02` et `data-03`.
- Les tailles de file Kafka, les partitions et les règles de rétention restent
  à valider avec une charge représentative.
