# Plateforme ELK

Cette plateforme reçoit les traces, métriques et logs du POC. ECK gère
Elasticsearch, Kibana, APM Server et Fleet Server ; les collecteurs
Elastic APM et Elastic Agent acheminent les données vers Elasticsearch.

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

APM Server est déployé par ECK. Les deux services lui envoient leurs signaux
avec l'agent Java Elastic APM. APM Server valide le token ECK puis remet
les événements à Logstash par Lumberjack. Logstash les écrit en HTTPS dans les
data streams APM Elasticsearch avec une clé API dédiée, créée hors Git par
`make apm-logstash-deploy`. Les deux services restent consultables dans
Observability > APM.

## Documentation externe

- [Déployer et administrer ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [Configurer APM Server](https://www.elastic.co/docs/solutions/observability/apm/apm-server/setup)
- [Configurer la sortie APM Server vers Logstash](https://www.elastic.co/docs/solutions/observability/apm/configure-logstash-output)
- [Modèles de déploiement Fleet](https://www.elastic.co/docs/reference/fleet/deployment-models)
