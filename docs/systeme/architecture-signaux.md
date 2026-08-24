# Architecture des signaux

## Vue d'ensemble

```text
order-service ─Elastic APM/HTTPS─> APM Server ─> Elasticsearch ─> Kibana
inventory-service ─Elastic APM/HTTPS─> APM Server ─> Elasticsearch
        │
        └─ stdout JSON ECS ─> Elastic Agent Kubernetes ─> logs-*

data-01, data-02 ─Agent piloté par Fleet──────────────────────────> logs-* / metrics-*
data-03 ─Filebeat + Metricbeat────────────────────────────────────> logs-* / metrics-*
```

Les services Elastic (Elasticsearch, Kibana, APM Server et Fleet Server) sont
gérés par ECK dans Kubernetes. Les deux applications utilisent l'agent Java
Elastic et envoient leurs traces directement à APM Server. Kafka reste une
dépendance métier instrumentée, pas un transport de télémétrie.

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

`data-01` et `data-02` reçoivent une policy Fleet avec les intégrations System,
MongoDB, Kafka/Jolokia et PostgreSQL. `data-03` utilise Filebeat pour les logs
et Metricbeat pour les métriques système, MongoDB et Kafka. Les profils sont
exclusifs sur un même hôte afin d'éviter les doublons. L'Agent Kubernetes lit
les logs des pods ; aucune collecte EDOT n'est déployée.

La matrice détaillée est dans [metriques-sources.md](metriques-sources.md).
