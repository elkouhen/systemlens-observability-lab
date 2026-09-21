# Plateforme ELK

Cette plateforme reçoit les traces, métriques et logs du POC. Elasticsearch,
Kibana, APM Server et Fleet Server sont déployés sur `elk-01` par Quadlet ; les
Collectors OpenTelemetry acheminent les signaux applicatifs et Kubernetes vers
Kafka, puis les traces vers APM Server et les métriques/logs vers Elasticsearch. Les
collecteurs EDOT Kubernetes sont configurés par manifests versionnés, sans
OpAMP. Les VM utilisent
Elastic Agent en mode EDOT standalone et exportent leurs logs et métriques en
OTLP vers le Collecteur Edge.

## Ordre de lecture

1. [`../kubernetes/README.md`](../kubernetes/README.md) : le point d'entrée
   Kustomize des ressources qui tournent dans le cluster.
2. [`fleet/README.md`](fleet/README.md) : les assets Fleet de compatibilité et
   le chemin EDOT standalone des VM MongoDB, Kafka et PostgreSQL.
3. [`scripts/README.md`](scripts/README.md) : l'initialisation des secrets et
   la synchronisation de Fleet.
4. [`dashboards/README.md`](dashboards/README.md) : les objets Kibana importés.

## Modèle mental

`applications Java → Gateway OTel Kubernetes → Collecteur Edge otel-edge-01 → Kafka poc-01 → exporteur OTel otel-backend-01 → APM Server elk-01 → Kibana` pour les traces ; les métriques et logs suivent l'export Elasticsearch.

Les trois services embarquent l'agent Java OpenTelemetry dans leurs images et
exportent leurs traces et métriques en OTLP/HTTP vers le Gateway Kubernetes.
Le Collector DaemonSet, le collecteur cluster et le Gateway sont des collecteurs
EDOT configurés par Kustomize. Le Collector DaemonSet lit les logs stdout et les métriques hôte, puis les
signaux sont envoyés au Collecteur Edge, puis dans les topics Kafka OTLP par
signal (`otel-traces`, `otel-metrics`, `otel-logs`). L'exporteur de sortie sur `otel-backend-01`
consomme ces topics et envoie les traces à APM Server sur `elk-01` ; les
métriques et les logs sont exportés vers Elasticsearch.

Chaque VM active exécute l’Elastic Agent installé par Ansible en mode EDOT
standalone. Il lit les logs locaux et les métriques hôte, puis publie en OTLP
vers le Collecteur Edge. Les VM ne passent pas par le Gateway OTLP Kubernetes,
mais partagent le chemin Edge, Kafka et Backend.

Lors d'un déploiement initial, `make elk-deploy` provisionne le stack Quadlet,
incluant APM Server sur `elk-01`,
applique le routage Traefik et crée ou réconcilie la clé
d'API Elasticsearch du Collector backend avant de démarrer les workloads.
Cette clé sert à l'export Kafka → Elasticsearch ; elle n'est pas une clé
d'enrôlement Fleet. Les VM utilisent exclusivement l'Elastic Agent EDOT
afin d'éviter une double collecte.

La cible `elastic-disk-ensure`, appelée par `make elk-deploy`, garantit le
disque système de `elk-01` à 30 GiB avant le démarrage d'Elasticsearch. Le
redimensionnement VirtualBox, la partition et XFS sont idempotents.

Les topics sont séparés par signal. L'exemple Elastic avec un topic partagé est
un pattern d'architecture, mais le receiver Kafka embarqué dans EDOT Collector
9.4.3 ne route pas automatiquement des payloads logs, métriques et traces
mélangés dans un même topic ; les séparer évite les erreurs de décodage et
conserve le même flux otel-edge → Kafka → backend → Elasticsearch.

Les règles de collecte Kubernetes et de buffer Kafka sont dans
`../kubernetes/base/observability/otel-kafka.yaml`. Le Gateway OTLP VM,
l'exporteur Kafka et l'enrôlement Fleet sont décrits dans `../../ansible/site.yml`.
La collecte filelog est limitée au namespace applicatif, conserve ses offsets
sur le nœud et ignore les événements Kafka répétitifs de désérialisation. Les
logs sont regroupés par lots de 50 toutes les 5 secondes ; les topics OTLP
Kafka ont une rétention de 24 heures et 512 MiB par partition (trois
partitions par topic OTLP, soit un seuil de 1,5 GiB par topic). Ces limites bornent
la volumétrie du POC sans modifier le chemin de collecte.
Pour migrer l'exporteur depuis Kubernetes, exécuter
`make otel-kafka-exporter-relocate`, puis `make otel-kafka-exporter-vm-status`.

La configuration Kibana Quadlet installe les packages Elastic `system`,
`kubernetes`, `mongodb`, `kafka` et `postgresql`, puis la cible
`make kibana-fleet-config-deploy` réconcilie la configuration Fleet et les
assets nécessaires au plan de contrôle. Les policies classiques de collecte VM
ne doivent pas être activées en parallèle du mode EDOT standalone.
Les données Elasticsearch ne sont pas copiées par Ansible : restaurer un
snapshot ou réindexer les données sur la nouvelle VM avant de considérer la
migration terminée.

## Documentation externe

- [Déployer et administrer ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [OpenTelemetry avec Elastic (EDOT)](https://www.elastic.co/docs/reference/opentelemetry)
- [Architecture Kafka avec OpenTelemetry](https://www.elastic.co/docs/reference/opentelemetry/architecture/kafka)
- [Modèles de déploiement Fleet](https://www.elastic.co/docs/reference/fleet/deployment-models)

## Rétention et maîtrise du disque

Les règles et la procédure opérateur sont décrites dans
[`retention/README.md`](retention/README.md). `make retention-deploy` applique
uniquement les limites Kafka, la rotation des logs des VM et les politiques ILM.
`make retention-verify` contrôle leur application effective.
