# Différences historiques entre les architectures v1 et v2

Ce document conserve la comparaison historique entre les deux premiers bundles
d'architecture. La référence actuelle incluant v3 est
[`architecture-v1-v2-v3.md`](architecture-v1-v2-v3.md). Les deux bundles utilisent une topologie minimale avec
l'unique VM `data-01`. Les flux détaillés sont représentés dans
[`observability-flows-v1-v2.md`](observability-flows-v1-v2.md).
La revue historique de mutualisation du code est détaillée dans
[`diff-code-v1-v2.md`](diff-code-v1-v2.md).

## Vue d'ensemble

| Sujet | v1 | v2 | État |
| --- | --- | --- | --- |
| Elastic/Kibana | Elastic Stack `8.11.3` | Elastic Stack `9.4.3` | Implémenté |
| Organisation | `v1/` contient la plateforme et Ansible ; les manifests applicatifs sont mutualisés sous `kubernetes/` | `v2/` contient sa propre plateforme et son Ansible ; les manifests applicatifs utilisent le même socle sous `kubernetes/` | Implémenté |
| Code Java, POM, Dockerfile | Partagé sous `apps/supermarket-demo/` | Partagé sous `apps/supermarket-demo/` | Inchangé |
| Makefile/Vagrantfile | Bundle `v1/` | Bundle `v2/` | Implémenté |
| Isolation Kubernetes | Namespace `elastic-stack`, application `h0tl-supermarche-app` | Les mêmes namespaces, selon le bundle actif | Implémenté |
| Accès local | `elasticsearch.observability.test`, `kibana.observability.test`, `fleet.observability.test` | Les mêmes URL, selon le bundle actif | Implémenté |
| Traces applicatives | Agent Elastic APM → APM Server → Logstash | OpenTelemetry Java Agent → EDOT Gateway → Kafka → EDOT Collector → Elasticsearch | Implémenté |
| Métriques applicatives/Kubernetes | Métriques APM via APM Server/Logstash ; métriques kubelet et état Kubernetes via Elastic Agent/Logstash | Métriques Java via OTel Agent → collector edge → Kafka `otel-metrics` ; métriques hôte et Kubernetes via EDOT DaemonSet → Kafka `otel-metrics` → collector backend | Implémenté |
| Métriques Prometheus | Elastic Agent Kubernetes scrape `/actuator/prometheus`, puis Logstash → data stream Prometheus dédié | Endpoint Actuator conservé, mais pas de scraping Prometheus dans le chemin v2 actuel ; les métriques Java exportées par OTel suivent OTLP → Kafka → EDOT Collector | Implémenté |
| Logs applicatifs/Kubernetes | Elastic Agent → Logstash | EDOT Kubernetes `filelog` → Kafka → EDOT Collector → Elasticsearch | Implémenté |
| Logs et métriques des VM | `data-01` : Filebeat/Metricbeat → Logstash `5045` → Elasticsearch | EDOT Agent sur `data-01` → Kafka `otel-logs` / `otel-metrics` → collector backend → Elasticsearch | Implémenté |
| Topologie VM | Une seule VM `data-01` | Une seule VM `data-01` | Implémenté |
| Stabilisation Kafka | Kafka transporte les événements métier ; la télémétrie utilise les sorties Elastic directes | Kafka transporte les événements métier et sert aussi de buffer OTLP pour les signaux, avec des topics dédiés et des consumer groups | Implémenté |
| Versions OTel | Non utilisé pour les signaux du POC | EDOT Collector `9.4.3`, agent Java OTel `2.28.1` | Implémenté |
| Corrélation logs/traces | Agent Elastic APM enrichit le MDC ; logs ECS avec `trace.id`/`span.id` | Logs ECS stdout parsés par EDOT ; `trace_id`/`span_id` sont conservés pour retrouver la trace | Implémenté |
| Dashboards et data streams | Data streams ECS v8 et dashboards classiques Elastic/Prometheus | Data streams OTel (`*.otel-*`) et dashboards OTel/compatibles ; les noms de métriques OTel ne sont pas renommés en métriques legacy | Implémenté |

## Contrat de transport v2

Les topics Kafka de télémétrie sont dédiés aux signaux et utilisent
l'encodage OTLP protobuf :

| Topic | Signal | Producteur | Consommateur |
| --- | --- | --- | --- |
| `otel-traces` | Traces OTLP | Collector edge applicatif | Collector backend Kafka → Elasticsearch |
| `otel-metrics` | Métriques OTLP | Collectors edge applicatif/Kubernetes et EDOT Agent VM | Collector backend Kafka → Elasticsearch |
| `otel-logs` | Logs OTLP | EDOT DaemonSet Kubernetes et EDOT Agent VM | Collector backend Kafka → Elasticsearch |

Les topics sont créés par un Job Kubernetes idempotent après le provisionnement
de `data-01`. Le Collector de sortie
utilise un batch et une file d'attente locale éphémère ; la rétention et
la reprise après indisponibilité d'Elasticsearch sont d'abord assurées par
Kafka. La capacité, le nombre de partitions et la réplication devront être
mesurés avant un usage de production.

La documentation Elastic montre aussi une variante avec un topic partagé. Cette
variante n'est pas retenue ici : avec EDOT Collector `9.4.3`, le receiver Kafka
ne distingue pas automatiquement des payloads de signaux différents mélangés
dans le même topic. La séparation par signal est donc nécessaire pour garder
une consommation OTLP fiable, tout en conservant l'architecture Kafka
documentée par Elastic.

### Chemins réellement utilisés

- APM Java v1 : agent Elastic APM → APM Server → Logstash `5044` →
  Elasticsearch.
- APM Java v2 : OTel Java Agent → collector edge `4317/4318` → Kafka
  `otel-traces` / `otel-metrics` → collector backend → Elasticsearch.
- VM v1 : Filebeat/Metricbeat `data-01` → Logstash `5045` → Elasticsearch.
- VM v2 : EDOT Agent local → Kafka `otel-logs` / `otel-metrics` directement ; les VM ne passent
  pas par le Gateway OTLP Kubernetes.
- Logs applicatifs v1 : stdout → Elastic Agent Kubernetes → Logstash `5045` →
  Elasticsearch.
- Logs applicatifs v2 : stdout ECS → EDOT DaemonSet `filelog` → Kafka
  `otel-logs` → collector backend → Elasticsearch.

Fleet Server reste nécessaire pour l'administration des agents Fleet présents
en v1. En v2, les métriques et logs de `data-01` sont produits par le service EDOT
Agent provisionné par Ansible ; les artefacts Fleet conservés dans le bundle
servent au bootstrap et à la gestion de la plateforme, pas au transport de ces
signaux.

## Vérification et changement de version

La v3 reprend la structure v2 pour les applications et Kubernetes, mais remplace
la collecte VM EDOT → Kafka par un Elastic Agent enrôlé dans Fleet →
Elasticsearch. Voir la [référence v1/v2/v3](architecture-v1-v2-v3.md) pour le
flux complet.

Les commandes de validation, de déploiement, de bascule et de diagnostic sont
centralisées dans le [guide de déploiement et d'exploitation](deploiement-et-exploitation.md).
Ce document conserve uniquement le contrat d'architecture ; il ne duplique pas
la procédure opérateur.

## Décisions et points ouverts

- La v2 utilise l'endpoint OTLP/HTTP Elasticsearch côté Collector de sortie ;
  Elasticsearch n'accepte pas OTLP/gRPC pour cette destination.
- Les logs sont collectés à partir de stdout Kubernetes par `filelog`; ils ne
  sont pas envoyés par le code Java.
- Les deux versions provisionnent uniquement `data-01`. MongoDB est standalone
  et Kafka est mono-broker ; la réplication et le quorum multi-nœuds ne font pas
  partie du périmètre actuel.
- Les tailles de file Kafka, les partitions et les règles de rétention restent
  à valider avec une charge représentative.
- La migration doit commencer par un déploiement v2 isolé. Le retour vers v1
  consiste à resélectionner v1 et à vérifier ses endpoints ; il ne faut pas
  supprimer les ressources v1 avant d'avoir validé la restauration et la
  consultation des données.
