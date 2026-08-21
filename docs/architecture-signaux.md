# Architecture des signaux

## Vue d'ensemble

```text
order-service ─Elastic APM/HTTPS─> APM Server ───────────────────────────> Elasticsearch
inventory-service ─OTLP/HTTP─> gateway OTel ─Kafka/OTLP─> backend OTel ─> Elasticsearch
        │                                │                        │                 │
        └─ stdout JSON ECS ─> Elastic Agent Kubernetes ─────────────┴─> logs-* ──┤
                                                                                └─> Kibana

VM OpenTelemetry ─EDOT (logs + métriques)────────────────────────> logs-* / metrics-*
VM Elastic Agent ─Agent piloté par Fleet──────────────────────────> logs-* / metrics-*
VM Beats ─Filebeat + Metricbeat──────────────────────────────────> logs-* / metrics-*
```

Les services Elastic (Elasticsearch, Kibana, APM Server et Fleet Server) sont
gérés par ECK dans Kubernetes. Le POC démontre deux chemins de traces :
`order-service` utilise l'agent Java Elastic et APM Server ;
`inventory-service` utilise l'agent Java OpenTelemetry puis Kafka avant
Elasticsearch. Les deux chemins sont visibles dans Kibana et servent à comparer
les modes d'ingestion.

## Traces, transactions et spans

Une **trace** regroupe toutes les opérations corrélées par un même `trace.id`.
Une **transaction** est le span racine d'une unité de travail côté service ; un
appel HTTP entrant ou une consommation Kafka en sont des exemples. Un **span**
représente une opération enfant : appel HTTP sortant, publication ou
consommation Kafka, requête MongoDB ou PostgreSQL.

Le contexte W3C (`traceparent`) est propagé entre les services. Les agents Java
instrumentent les bibliothèques HTTP, Kafka et bases de données, puis ajoutent
les attributs de protocole. Les noms doivent rester orientés métier/lecture :
`GET /api/orders` pour HTTP, nom du topic pour Kafka, et opération/ressource
pour les bases de données.

### Chemin de la trace du POC

1. Un service applicatif traite une requête HTTP ou une tâche planifiée.
2. Le contexte est propagé lors de la publication Kafka ou de l'appel à un
   autre service.
3. Le service consommateur traite le message et produit les spans Kafka,
   MongoDB et PostgreSQL associés.
4. `order-service` envoie ses traces à APM Server en HTTPS. Les traces
   d'`inventory-service` sont émises en OTLP vers `otel-collector-gateway`.
5. Le gateway enrichit les ressources Kubernetes puis publie les traces brutes
   d'`inventory-service` en `otlp_proto` dans le topic Kafka `otel-traces`.
6. Les collectors `otel-collector-traces-backend`, dans le même consumer group,
   relisent le topic. Le processeur/connecteur `elasticapm` génère les métriques
   transactionnelles APM ; l'exporteur Elasticsearch indexe les traces et ces
   métriques.
7. Kibana lit les data streams `traces-*` et `metrics-*` pour les vues APM des
   deux chemins.

Kafka amortit une indisponibilité courte d'Elasticsearch, mais ajoute un délai
entre l'émission et l'apparition dans Kibana. Les métriques applicatives OTLP ne
passent pas par Kafka : elles vont du gateway à Elasticsearch pour rester à
faible latence.

## Logs

Les applications écrivent des événements JSON ECS sur stdout. L'Elastic Agent
DaemonSet Kubernetes lit les logs de conteneurs, ajoute les métadonnées
Kubernetes et normalise `trace.id` / `span.id` provenant du MDC Java. Les VM
utilisent Filebeat pour les journaux Rocky Linux, MongoDB, Kafka et PostgreSQL.

L'export OTLP Logs applicatif est volontairement désactivé afin d'éviter une
double collecte du même événement. Les traces permettent néanmoins la
navigation du log vers la trace grâce aux identifiants de corrélation.

## Métriques

La VM OpenTelemetry collecte les logs locaux, les métriques système et les
métriques MongoDB, Kafka et PostgreSQL par EDOT. Les données sont indexées au
format OpenTelemetry. Un pipeline d'ingestion recopie
`resource.attributes['host.name']` vers `host.name` pour conserver la
compatibilité avec les dashboards Infrastructure existants.

La VM Elastic Agent reçoit une policy Fleet avec les intégrations System,
MongoDB et Kafka. La VM Beats utilise Filebeat pour les logs, et Metricbeat
pour les métriques système, MongoDB et Kafka. Les trois profils sont exclusifs
sur un même hôte afin d'éviter les doublons.

Les intégrations Fleet collectent les métriques métier MongoDB et Kafka.
PostgreSQL appartient au profil EDOT de la VM OpenTelemetry. L'infrastructure
Kubernetes est observée par des collectors EDOT DaemonSet (hôte/Kubelet) et
cluster. Les métriques Micrometer des applications sont émises en OTLP vers le
gateway.

La matrice détaillée est dans [metriques-sources.md](metriques-sources.md).
