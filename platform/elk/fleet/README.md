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
Kafka et met à jour leurs pipelines Elasticsearch associés. Il ne route pas les
logs, métriques ni traces applicatifs Kubernetes : ce routage appartient au
pipeline Logstash `apm-logstash.yaml`.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
