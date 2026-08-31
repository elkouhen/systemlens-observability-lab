# Différences entre les architectures v1 et v2

Ce document est la référence de comparaison entre les deux bundles
d'architecture. Les deux bundles supportent un profil léger, utilisé par
défaut dans ce POC.

## Vue d'ensemble

| Sujet | v1 | v2 | État |
| --- | --- | --- | --- |
| Elastic/Kibana | Elastic Stack `8.11.3` | Elastic Stack `9.4.3` | Implémenté |
| Organisation | `v1/` contient la plateforme, Ansible et les manifests applicatifs | `v2/` contient sa propre plateforme, son Ansible et ses manifests applicatifs | Implémenté |
| Code Java, POM, Dockerfile | Partagé sous `apps/supermarket-demo/` | Partagé sous `apps/supermarket-demo/` | Inchangé |
| Makefile/Vagrantfile | Bundle `v1/` | Bundle `v2/` | Implémenté |
| Isolation Kubernetes | Namespace `elastic-stack`, application `h0tl-supermarche-app` | Namespace `elastic-stack-v2`, application `h0tl-supermarche-app-v2` | Implémenté |
| Accès local | `elasticsearch.poc.test`, `kibana.poc.test`, `fleet.poc.test` | Les mêmes URL, selon le bundle actif | Implémenté |
| Traces applicatives | Agent Elastic APM → APM Server → Logstash | OpenTelemetry Java Agent → EDOT Gateway → Kafka → EDOT Collector → Elasticsearch | Implémenté |
| Métriques applicatives/Kubernetes | Elastic Agent et pipelines Logstash | EDOT Java Agent/EDOT Kubernetes → Kafka → EDOT Collector → Elasticsearch | Implémenté |
| Métriques Prometheus | Endpoint Actuator `/actuator/prometheus` collecté par Metricbeat/Elastic Agent | Endpoint Actuator conservé ; les métriques Java exportées utilisent OTLP → Kafka → EDOT Collector, sans scraping Prometheus dans le pipeline actuel | Implémenté |
| Logs applicatifs/Kubernetes | Elastic Agent → Logstash | EDOT Kubernetes `filelog` → Kafka → EDOT Collector → Elasticsearch | Implémenté |
| Logs et métriques des VM | `data-01` et `data-02` via Elastic Agent/Fleet ; `data-03` via Filebeat/Metricbeat | EDOT Agent sur chaque VM active → Kafka OTLP → EDOT Collector → Elasticsearch | Implémenté |
| Topologie VM par défaut | `POC_PROFILE=minimal` : `data-01` seule | `POC_PROFILE=minimal` : `data-01` seule | Implémenté |
| Topologie VM distribuée | `POC_PROFILE=distributed` : trois VM | `POC_PROFILE=distributed` : trois VM | Disponible |
| Stabilisation Kafka | Kafka transporte les événements métier ; les signaux passent par Fleet/Logstash | Kafka transporte les événements métier et les signaux OTLP avec des topics dédiés | Implémenté |
| Versions OTel | Non utilisé pour les signaux du POC | EDOT Collector `9.4.3`, agent Java OTel `2.28.1` | Implémenté |

## Contrat de transport v2

Les topics Kafka de télémétrie sont dédiés aux signaux et utilisent
l'encodage OTLP protobuf :

| Topic | Signal | Producteur | Consommateur |
| --- | --- | --- | --- |
| `otel-traces` | Traces | Collector OTel gateway | Collector OTel Elasticsearch |
| `otel-metrics` | Métriques | Collector OTel gateway/DaemonSet | Collector OTel Elasticsearch |
| `otel-logs` | Logs | Collector OTel DaemonSet | Collector OTel Elasticsearch |
| `edot-vm-logs` | Logs des VM | EDOT Agent VM | Collector EDOT Elasticsearch |
| `edot-vm-metrics` | Métriques des VM | EDOT Agent VM | Collector EDOT Elasticsearch |

Les topics sont créés par un Job Kubernetes idempotent. Le Collector de sortie
utilise un batch et une file d'attente locale éphémère ; la rétention et
la reprise après indisponibilité d'Elasticsearch sont d'abord assurées par
Kafka. La capacité, le nombre de partitions et la réplication devront être
mesurés avant un usage de production.

## Vérification prévue

```bash
make architecture-switch VERSION=v2
POC_PROFILE=minimal make kubernetes-validate
POC_PROFILE=minimal make elk-deploy
POC_PROFILE=minimal make apps-deploy
kubectl -n elastic-stack-v2 get deploy,daemonset,job otel-gateway otel-kafka-exporter edot-vm-telemetry-topics
POC_PROFILE=minimal make vm-provision
kubectl -n elastic-stack-v2 logs deployment/otel-kafka-exporter --tail=50
```

Résultat attendu : `data-01` est la seule VM active du profil minimal, les
topics OTLP existent, les Collectors sont prêts, et les data streams
`traces-*.otel-*`, `metrics-*.otel-*` et `logs-*.otel-*` reçoivent les signaux
de la démo.

Le contrôle HTTP de Fleet doit viser `/api/status` ; un `404` sur la racine
`fleet.poc.test/` est normal, car Fleet Server ne fournit pas d'interface web.

## Séquence de migration

1. Vérifier la santé de v1 et prendre un snapshot Elasticsearch.
2. Valider les manifests et le playbook v2 :
   `make ARCH_VERSION=v2 kubernetes-validate`, puis
   `make -C v2 ansible-validate`.
3. Préparer le DNS ou `/etc/hosts` pour les hôtes `*-v2.poc.test` et le
   certificat TLS correspondant.
4. Déployer v2 avec `make -C v2 elk-deploy`, puis les images et manifests de la
   démo avec `make -C v2 apps-build`, `make -C v2 images-import` et
   `make -C v2 apps-deploy`.
5. Produire une charge de test et vérifier les topics Kafka, le consumer lag,
   les métriques Prometheus et les data streams dans Kibana v2.
6. En cas d'échec, revenir à v1 avec `make architecture-switch VERSION=v1`;
   ne pas supprimer les ressources v2 avant l'analyse des offsets Kafka.

## Décisions et points ouverts

- La v2 utilise l'endpoint OTLP/HTTP Elasticsearch ; Elasticsearch n'accepte
  pas OTLP/gRPC pour cette destination.
- Les logs sont collectés à partir de stdout Kubernetes par `filelog`; ils ne
  sont pas envoyés par le code Java.
- En profil minimal, seule `data-01` est provisionnée ; les profils distribués
  restent disponibles pour tester la réplication MongoDB et le quorum Kafka.
- Les tailles de file Kafka, les partitions et les règles de rétention restent
  à valider avec une charge représentative.
- La migration doit commencer par un déploiement v2 isolé. Le retour vers v1
  consiste à resélectionner v1 et à vérifier ses endpoints ; il ne faut pas
  supprimer les ressources v1 avant d'avoir validé la restauration et la
  consultation des données.
