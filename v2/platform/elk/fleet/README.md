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

Les package policies System, MongoDB, Kafka et PostgreSQL sont associées à
`data-fleet`, appliquée à toutes les VM actives du profil. Chaque VM exécute un
seul Elastic Agent : `localhost` désigne donc le service local de cet hôte.
Les VM ne sont plus enrôlées dans Fleet pour leur télémétrie. Elles exécutent
EDOT Collector en mode agent et publient de l'OTLP dans Kafka ; le Collector
EDOT Kubernetes consomme ces topics et exporte vers Elasticsearch.

Appliquer `make kibana-fleet-config-deploy` (inclus dans `make elk-deploy`) pour
préconfigurer les policies sur un nouveau Kibana. `make fleet-sync` met à jour
les pipelines Elasticsearch `@custom`, la condition PostgreSQL de la policy
déclarée, les Agents hérités et la compatibilité Kafka Raft. Le flux OTel des
applications et de Kubernetes reste séparé du flux ECS Fleet des VM.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
