# Plateforme ELK

Cette plateforme reçoit les traces, métriques et logs du POC. ECK gère
Elasticsearch, Kibana, APM Server et Fleet Server ; les collecteurs
Elastic APM et Elastic Agent acheminent les données vers Elasticsearch.

## Ordre de lecture

1. [`../kubernetes/README.md`](../kubernetes/README.md) : le point d'entrée
   Kustomize des ressources qui tournent dans le cluster.
2. [`fleet/README.md`](fleet/README.md) : les policies Fleet conservées comme
   référence pour la plateforme Kubernetes.
3. [`scripts/README.md`](scripts/README.md) : l'initialisation des secrets et
   la synchronisation de Fleet.
4. [`dashboards/README.md`](dashboards/README.md) : les objets Kibana importés.

## Modèle mental

`applications Java → agent APM / Elastic Agent Kubernetes → Logstash → Elasticsearch → Kibana`.

`data-01` utilise exclusivement Filebeat et Metricbeat. Les deux Beats envoient
les logs et métriques au pipeline `kubernetes-logs` de Logstash sur le port
`5045`, puis Logstash écrit dans Elasticsearch. La VM doit pouvoir résoudre et
atteindre l'adresse Logstash configurée par `LOGSTASH_URL` (par défaut
`apm-logstash.elastic-stack.svc:5045`) depuis le réseau Kubernetes.

Lors d'un déploiement initial, `make deploy` attend d'abord que Kibana soit
prêt, puis démarre `data-01` avec Filebeat et Metricbeat.

APM Server est déployé par ECK. Les trois services lui envoient leurs signaux
avec l'agent Java Elastic APM. APM Server valide le token ECK puis remet
les événements à Logstash par Lumberjack. Les Elastic Agents Kubernetes y
envoient aussi les logs stdout des pods et les métriques du cluster par une
entrée Beats dédiée. Logstash écrit ces signaux en HTTPS dans les data streams
Elasticsearch avec une clé API dédiée, créée hors Git par
`make apm-logstash-deploy`. Les trois services restent consultables dans
Observability > APM.

Les règles de routage des applications Kubernetes sont dans
`../kubernetes/base/observability/apm-logstash.yaml`, et non dans Fleet ni dans
des pipelines Elasticsearch. Fleet reste réservé aux composants Kubernetes ;
il n'est pas enrôlé sur `data-01`.

## Documentation externe

- [Déployer et administrer ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [Configurer APM Server](https://www.elastic.co/docs/solutions/observability/apm/apm-server/setup)
- [Configurer la sortie APM Server vers Logstash](https://www.elastic.co/docs/solutions/observability/apm/configure-logstash-output)
- [Modèles de déploiement Fleet](https://www.elastic.co/docs/reference/fleet/deployment-models)
