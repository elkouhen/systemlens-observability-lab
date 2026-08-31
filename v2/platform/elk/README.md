# Plateforme ELK

Cette plateforme reçoit les traces, métriques et logs du POC. ECK gère
Elasticsearch et Kibana ; les Collectors OpenTelemetry acheminent les signaux
applicatifs et Kubernetes vers Kafka, puis vers Elasticsearch via OTLP. Fleet
reste temporairement réservé aux VM.

## Ordre de lecture

1. [`../kubernetes/README.md`](../kubernetes/README.md) : le point d'entrée
   Kustomize des ressources qui tournent dans le cluster.
2. [`fleet/README.md`](fleet/README.md) : les policies qui observent les VM
   MongoDB et Kafka.
3. [`scripts/README.md`](scripts/README.md) : l'initialisation des secrets et
   la synchronisation de Fleet.
4. [`dashboards/README.md`](dashboards/README.md) : les objets Kibana importés.

## Modèle mental

`applications Java / Collector Kubernetes → Collector OTel → Kafka → Collector OTel → Elasticsearch → Kibana`.

Les Elastic Agents de `data-01` et `data-02` constituent un flux distinct :
Fleet les pilote, tandis qu'ils envoient leurs données directement vers
Elasticsearch. `data-03` utilise exclusivement Filebeat et Metricbeat, qui
envoient également leurs données directement vers Elasticsearch avec une clé
API dédiée.

Les trois services reçoivent l'agent Java OpenTelemetry par init container et
exportent leurs traces et métriques en OTLP/HTTP. Le Collector DaemonSet lit
les logs stdout et les métriques hôte, puis tous les signaux sont envoyés dans
les topics Kafka `otel-traces`, `otel-metrics` et `otel-logs`. Le Collector de
sortie consomme ces topics et écrit vers l'endpoint OTLP/HTTP Elasticsearch.

Les règles de collecte, de buffer Kafka et de routage OTLP sont dans
`../kubernetes/base/observability/otel-kafka.yaml`. Fleet reste réservé aux
policies des Elastic Agents des VM.

## Documentation externe

- [Déployer et administrer ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [Configurer APM Server](https://www.elastic.co/docs/solutions/observability/apm/apm-server/setup)
- [Configurer la sortie APM Server vers Logstash](https://www.elastic.co/docs/solutions/observability/apm/configure-logstash-output)
- [Modèles de déploiement Fleet](https://www.elastic.co/docs/reference/fleet/deployment-models)
