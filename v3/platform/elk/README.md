# Plateforme ELK

Cette plateforme reçoit les traces, métriques et logs du POC. Elasticsearch,
Kibana, APM Server et Fleet Server sont déployés sur `elk-01` par Quadlet ; les
Collectors OpenTelemetry acheminent les signaux applicatifs et Kubernetes vers
Kafka, puis les traces vers APM Server et les métriques/logs vers Elasticsearch. Les VM
utilisent Fleet et exportent directement vers Elasticsearch.
Fleet Server gère les Elastic Agents des VM, qui exportent directement vers
Elasticsearch.

## Ordre de lecture

1. [`../kubernetes/README.md`](../kubernetes/README.md) : le point d'entrée
   Kustomize des ressources qui tournent dans le cluster.
2. [`fleet/README.md`](fleet/README.md) : les policies qui observent les VM
   MongoDB et Kafka.
3. [`scripts/README.md`](scripts/README.md) : l'initialisation des secrets et
   la synchronisation de Fleet.
4. [`dashboards/README.md`](dashboards/README.md) : les objets Kibana importés.

## Modèle mental

`applications Java → Gateway OTel Kubernetes → Kafka poc-01 → exporteur OTel otel-backend-01 → APM Server elk-01 → Kibana` pour les traces ; les métriques et logs suivent l'export Elasticsearch.

Les trois services embarquent l'agent Java OpenTelemetry dans leurs images et
exportent leurs traces et métriques en OTLP/HTTP vers le Gateway Kubernetes.
Le Collector DaemonSet lit les logs stdout et les métriques hôte, puis les
signaux sont envoyés dans les topics Kafka OTLP par signal (`otel-traces`,
`otel-metrics`, `otel-logs`). L'exporteur de sortie sur `otel-backend-01`
consomme ces topics et envoie les traces à APM Server sur `elk-01` ; les
métriques et les logs sont exportés vers Elasticsearch.

Chaque VM active exécute l’Elastic Agent provisionné et enrôlé dans Fleet par
Ansible. Il lit les logs locaux et les métriques système/Kafka/MongoDB/PostgreSQL,
puis publie directement vers Elasticsearch. Les VM ne passent pas par le
Gateway OTLP Kubernetes ni par Kafka pour leur télémétrie.

Lors d'un déploiement initial, `make elk-deploy` provisionne le stack Quadlet,
incluant APM Server sur `elk-01`,
applique le routage Traefik et crée ou réconcilie la clé
d'API Elasticsearch du Collector backend avant de démarrer les workloads.
Cette clé sert à l'export Kafka → Elasticsearch ; elle n'est pas une clé
d'enrôlement Fleet. Les VM v3 utilisent exclusivement l'Elastic Agent Fleet
afin d'éviter une double collecte.

La cible `elastic-disk-ensure`, appelée par `make elk-deploy`, garantit le
disque système de `elk-01` à 30 GiB avant le démarrage d'Elasticsearch. Le
redimensionnement VirtualBox, la partition et XFS sont idempotents.

Les topics sont séparés par signal. L'exemple Elastic avec un topic partagé est
un pattern d'architecture, mais le receiver Kafka embarqué dans EDOT Collector
9.4.3 ne route pas automatiquement des payloads logs, métriques et traces
mélangés dans un même topic ; les séparer évite les erreurs de décodage et
conserve le même flux edge → Kafka → backend → Elasticsearch.

Les règles de collecte Kubernetes et de buffer Kafka sont dans
`../kubernetes/base/observability/otel-kafka.yaml`. Le Gateway OTLP VM,
l'exporteur Kafka et l'enrôlement Fleet sont décrits dans `../../ansible/site.yml`.
Pour migrer l'exporteur depuis Kubernetes, exécuter
`make otel-kafka-exporter-relocate`, puis `make otel-kafka-exporter-vm-status`.

`make kibana-fleet-config-deploy` réconcilie la policy `data-fleet` et les
package policies des intégrations système, MongoDB, Kafka et PostgreSQL.
Les données Elasticsearch ne sont pas copiées par Ansible : restaurer un
snapshot ou réindexer les données sur la nouvelle VM avant de considérer la
migration terminée.

## Documentation externe

- [Déployer et administrer ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [OpenTelemetry avec Elastic (EDOT)](https://www.elastic.co/docs/reference/opentelemetry)
- [Architecture Kafka avec OpenTelemetry](https://www.elastic.co/docs/reference/opentelemetry/architecture/kafka)
- [Modèles de déploiement Fleet](https://www.elastic.co/docs/reference/fleet/deployment-models)
