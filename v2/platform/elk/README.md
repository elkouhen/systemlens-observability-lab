# Plateforme ELK

Cette plateforme reçoit les traces, métriques et logs du POC. ECK gère
Elasticsearch et Kibana ; les Collectors OpenTelemetry acheminent les signaux
applicatifs, Kubernetes et VM vers Kafka, puis vers Elasticsearch via OTLP.
Fleet Server est conservé pour la plateforme, mais ne transporte pas la
télémétrie des VM v2.

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

Les trois services reçoivent l'agent Java OpenTelemetry par init container et
exportent leurs traces et métriques en OTLP/HTTP. Le Collector DaemonSet lit
les logs stdout et les métriques hôte, puis tous les signaux sont envoyés dans
les topics Kafka OTLP par signal (`otel-traces`, `otel-metrics`, `otel-logs`). Le Collector de
sortie consomme ces topics et écrit vers l'endpoint OTLP/HTTP Elasticsearch.

Chaque VM active exécute le service EDOT Agent provisionné par Ansible. Il lit
les logs locaux et les métriques système/Kafka/MongoDB/PostgreSQL, puis publie
directement dans `otel-logs` et `otel-metrics`. Les VM ne passent pas par
le Gateway OTLP Kubernetes.

Les topics sont séparés par signal. L'exemple Elastic avec un topic partagé est
un pattern d'architecture, mais le receiver Kafka embarqué dans EDOT Collector
9.4.3 ne route pas automatiquement des payloads logs, métriques et traces
mélangés dans un même topic ; les séparer évite les erreurs de décodage et
conserve le même flux edge → Kafka → backend → Elasticsearch.

Les règles de collecte, de buffer Kafka et de routage OTLP sont dans
`../kubernetes/base/observability/otel-kafka.yaml`. Le provisioning EDOT des
VM est décrit dans `../../ansible/site.yml` et
`../../ansible/templates/otel-agent.yml.j2`.

## Documentation externe

- [Déployer et administrer ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [Configurer APM Server](https://www.elastic.co/docs/solutions/observability/apm/apm-server/setup)
- [Configurer la sortie APM Server vers Logstash](https://www.elastic.co/docs/solutions/observability/apm/configure-logstash-output)
- [Modèles de déploiement Fleet](https://www.elastic.co/docs/reference/fleet/deployment-models)
