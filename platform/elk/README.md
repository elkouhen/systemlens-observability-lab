# Plateforme ELK

Cette plateforme reçoit les traces, métriques et logs du POC. ECK gère
Elasticsearch, Kibana, APM Server et Fleet Server ; les collecteurs
OpenTelemetry et Elastic Agent acheminent les données vers Elasticsearch.

## Ordre de lecture

1. [`../kubernetes/README.md`](../kubernetes/README.md) : le point d'entrée
   Kustomize des ressources qui tournent dans le cluster.
2. [`fleet/README.md`](fleet/README.md) : les policies qui observent les VM
   MongoDB et Kafka.
3. [`scripts/README.md`](scripts/README.md) : l'initialisation des secrets et
   la synchronisation de Fleet.
4. [`dashboards/README.md`](dashboards/README.md) : les objets Kibana importés.

## Modèle mental

`application / VM → collecteur ou Elastic Agent → Elasticsearch → Kibana`.

APM Server est déployé par ECK et exposé pour un usage APM classique
(agents envoyant directement en HTTP/OTLP à APM Server), mais **les
applications de démonstration ne l'utilisent pas** : `order-service` et
`inventory-service` exportent leurs traces et métriques en OTLP vers le gateway
OpenTelemetry, qui les convertit et les écrit directement dans Elasticsearch
(`logs-*`, `metrics-*`, `traces-*`) sans transiter par APM Server. Les vues
Observability > APM de Kibana fonctionnent parce qu'elles lisent les mêmes
data streams, quel que soit le composant qui les a écrits ; ne pas supposer un
chaînage entre le gateway et APM Server dans ce POC.

## Documentation externe

- [Déployer et administrer ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [Configurer APM Server](https://www.elastic.co/docs/solutions/observability/apm/apm-server/setup)
- [Modèles de déploiement Fleet](https://www.elastic.co/docs/reference/fleet/deployment-models)
