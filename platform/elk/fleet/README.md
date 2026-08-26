# Policies Fleet et Elastic Agent

La configuration Fleet de référence est déclarée dans
[`../../kubernetes/base/observability/kibana.yaml`](../../kubernetes/base/observability/kibana.yaml),
dans `xpack.fleet`. ECK la transmet à Kibana au démarrage : aucun script hôte
ne crée les package policies standards MongoDB/Kafka.

## Parcours de lecture

- [`MONGODB.md`](MONGODB.md) : fonctionnement et adaptation de la policy
  `mongodb-fleet`.
- [`KAFKA.md`](KAFKA.md) : fonctionnement et adaptation de la policy
  `kafka-fleet` et de Jolokia.
- `mongodb-package-policy.json` et `kafka-package-policy.json` : modèles API
  réservés au playbook Ansible de policies dédiées par VM ; ils ne sont pas la
  source de vérité du déploiement Kubernetes.
- `kafka-topic-ingest-pipeline.json` : enrichissement du data stream Kafka.
- `apm-application-metrics-reroute-pipeline.json` : pipeline
  `metrics-apm.app@custom` qui fait converger les métriques applicatives des
  services exécutés en conteneur Kubernetes vers un data stream par cluster et
  `service.environment`, par exemple `metrics-apm.app.kubernetes-local-dev`.
- `kubernetes-application-logs-reroute-pipeline.json` : pipeline appliqué aux
  logs stdout collectés dans `logs-kubernetes.container_logs`, qui les route
  vers `logs-kubernetes.container_logs-local-dev`.
- `system-package-policy.json` : payload API de l'intégration System,
  synchronisé avec `kibana.yaml` par le script Fleet.
- `elastic-agent.yml` : exemple de configuration standalone, distinct de Fleet.

Les trois package policies System, MongoDB et Kafka sont associées à l'agent
policy `mongodb-hosts`. La VM Elastic Agent exécute un seul Agent :
`localhost` désigne donc le service local de cet hôte, jamais le poste qui
exécute `make fleet-sync`. PostgreSQL appartient à la VM `data-01`.

Appliquer `make kibana-fleet-config-deploy` (inclus dans `make elk-deploy`) pour
préconfigurer les policies sur un nouveau Kibana. `make fleet-sync` crée
l'intégration System si elle est absente, remplace les policies MongoDB et
Kafka afin d'appliquer la migration des logs, puis met à jour les pipelines
Elasticsearch `@custom`, dont le routage des métriques applicatives APM des
conteneurs Kubernetes vers le data stream partagé de leur cluster et de leur
environnement, par exemple `metrics-apm.app.kubernetes-local-dev`, ainsi que
les logs stdout Kubernetes vers `logs-kubernetes.container_logs-local-dev`.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
