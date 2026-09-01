# Policies Fleet et Elastic Agent

La configuration Fleet de référence est déclarée dans
[`../../kubernetes/base/observability/kibana.yaml`](../../kubernetes/base/observability/kibana.yaml),
dans `xpack.fleet`. ECK la transmet à Kibana au démarrage : aucun script hôte
ne crée les package policies standards MongoDB/Kafka.

## Parcours de lecture

- [`MONGODB.md`](MONGODB.md) : fonctionnement de l'intégration MongoDB.
- [`KAFKA.md`](KAFKA.md) : fonctionnement de l'intégration Kafka et de
  Jolokia.
- `kafka-topic-ingest-pipeline.json` : enrichissement du data stream Kafka.

Les package policies System, MongoDB et Kafka restent déclarées pour référence
et pour les composants Kubernetes, mais aucun Elastic Agent VM n'est enrôlé en
v1. `data-01` utilise exclusivement Filebeat et Metricbeat, qui publient vers
Logstash `5045`.

Appliquer `make kibana-fleet-config-deploy` (inclus dans `make elk-deploy`) pour
préconfigurer les policies sur un nouveau Kibana. `make fleet-sync` met à jour
les pipelines Elasticsearch `@custom`, la condition PostgreSQL de la policy
déclarée, les Agents hérités et la compatibilité Kafka Raft. Il ne route pas
les logs, métriques ni traces applicatifs Kubernetes : ce routage appartient au
pipeline Logstash `apm-logstash.yaml`.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
