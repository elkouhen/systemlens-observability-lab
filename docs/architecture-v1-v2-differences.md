# Différences entre les architectures v1 et v2

Ce document est la référence de comparaison entre les implémentations des deux
bundles d'architecture. Les deux bundles supportent un profil léger, utilisé
par défaut dans ce POC. Les flux détaillés sont représentés dans
[`observability-flows-v1-v2.md`](observability-flows-v1-v2.md).

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
| Métriques applicatives/Kubernetes | Métriques APM via APM Server/Logstash ; métriques kubelet et état Kubernetes via Elastic Agent/Logstash | Métriques Java via OTel Agent → collector edge → Kafka `otel-metrics` ; métriques hôte et Kubernetes via EDOT DaemonSet → Kafka `otel-metrics` → collector backend | Implémenté |
| Métriques Prometheus | Elastic Agent Kubernetes scrape `/actuator/prometheus`, puis Logstash → data stream Prometheus dédié | Endpoint Actuator conservé, mais pas de scraping Prometheus dans le chemin v2 actuel ; les métriques Java exportées par OTel suivent OTLP → Kafka → EDOT Collector | Implémenté |
| Logs applicatifs/Kubernetes | Elastic Agent → Logstash | EDOT Kubernetes `filelog` → Kafka → EDOT Collector → Elasticsearch | Implémenté |
| Logs et métriques des VM | Profil minimal : `data-01` via Elastic Agent/Fleet → Elasticsearch ; profil distribué : `data-01`/`data-02` via Fleet et `data-03` via Filebeat/Metricbeat | EDOT Agent sur chaque VM active → Kafka `otel-logs` / `otel-metrics` → collector backend → Elasticsearch | Implémenté |
| Topologie VM par défaut | `POC_PROFILE=minimal` : `data-01` seule | `POC_PROFILE=minimal` : `data-01` seule | Implémenté |
| Topologie VM distribuée | `POC_PROFILE=distributed` : trois VM | `POC_PROFILE=distributed` : trois VM | Disponible |
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

Les topics sont créés par un Job Kubernetes idempotent. Le Collector de sortie
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
- VM v1 : Elastic Agent/Fleet ou Beats selon la VM → Elasticsearch.
- VM v2 : EDOT Agent local → Kafka `otel-logs` / `otel-metrics` directement ; les VM ne passent
  pas par le Gateway OTLP Kubernetes.
- Logs applicatifs v1 : stdout → Elastic Agent Kubernetes → Logstash `5045` →
  Elasticsearch.
- Logs applicatifs v2 : stdout ECS → EDOT DaemonSet `filelog` → Kafka
  `otel-logs` → collector backend → Elasticsearch.

Fleet Server reste nécessaire pour l'administration des agents Fleet présents
en v1. En v2, les métriques et logs des VM sont produits par le service EDOT
Agent provisionné par Ansible ; les artefacts Fleet conservés dans le bundle
servent au bootstrap et à la gestion de la plateforme, pas au transport de ces
signaux.

## Vérification prévue

```bash
make architecture-switch VERSION=v2
POC_PROFILE=minimal make kubernetes-validate
POC_PROFILE=minimal make elk-deploy
POC_PROFILE=minimal make apps-deploy
kubectl -n elastic-stack-v2 get deploy,daemonset,job otel-gateway otel-kafka-exporter otel-telemetry-topics-v2
POC_PROFILE=minimal make vm-provision
kubectl -n elastic-stack-v2 logs deployment/otel-kafka-exporter --tail=50
```

Résultat attendu : `data-01` est la seule VM active du profil minimal dans les
deux versions, les topics OTLP existent en v2, les Collectors sont prêts, et
les data streams de traces, métriques et logs reçoivent les signaux de la démo.

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

- La v2 utilise l'endpoint OTLP/HTTP Elasticsearch côté Collector de sortie ;
  Elasticsearch n'accepte pas OTLP/gRPC pour cette destination.
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
