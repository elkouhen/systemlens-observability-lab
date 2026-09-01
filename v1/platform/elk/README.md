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

`applications Java → agent APM / Elastic Agent Kubernetes → Logstash → Elasticsearch → Kibana`.

Les Elastic Agents de `data-01` et `data-02` constituent un flux distinct :
Fleet les pilote, tandis qu'ils envoient leurs données directement vers
Elasticsearch. `data-03` utilise exclusivement Filebeat et Metricbeat, qui
envoient également leurs données directement vers Elasticsearch avec une clé
API dédiée.

Lors d'un déploiement initial, `make deploy` attend d'abord que Kibana soit
prêt, crée la clé d'API Elasticsearch nécessaire à Filebeat/Metricbeat, puis
démarre les VM. Il crée ensuite une clé d'enrôlement Fleet via l'API Kibana et
réenrôle `data-01` (et `data-02` en profil distribué) avec la policy `data-fleet`.

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
des pipelines Elasticsearch. Fleet reste réservé aux policies des Elastic
Agents des VM.

## Documentation externe

- [Déployer et administrer ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [Configurer APM Server](https://www.elastic.co/docs/solutions/observability/apm/apm-server/setup)
- [Configurer la sortie APM Server vers Logstash](https://www.elastic.co/docs/solutions/observability/apm/configure-logstash-output)
- [Modèles de déploiement Fleet](https://www.elastic.co/docs/reference/fleet/deployment-models)
