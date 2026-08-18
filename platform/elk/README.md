# Plateforme ELK

Cette plateforme reçoit les traces, métriques et logs du POC. ECK gère
Elasticsearch, Kibana, APM Server et Fleet Server ; les collecteurs
OpenTelemetry et Elastic Agent acheminent les données vers Elasticsearch.

## Ordre de lecture

1. [`kubernetes/README.md`](kubernetes/README.md) : les ressources qui tournent
   dans le cluster et leurs dépendances.
2. [`fleet/README.md`](fleet/README.md) : les policies qui observent les VM
   MongoDB et Kafka.
3. [`scripts/README.md`](scripts/README.md) : l'initialisation des secrets et
   la synchronisation de Fleet.
4. [`dashboards/README.md`](dashboards/README.md) : les objets Kibana importés.

## Modèle mental

`application / VM → collecteur ou Elastic Agent → Elasticsearch → Kibana`.
APM Server reçoit les données APM, tandis que le gateway OpenTelemetry exporte
directement les signaux OTLP vers Elasticsearch.

## Documentation externe

- [Déployer et administrer ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [Configurer APM Server](https://www.elastic.co/docs/solutions/observability/apm/apm-server/setup)
- [Modèles de déploiement Fleet](https://www.elastic.co/docs/reference/fleet/deployment-models)
