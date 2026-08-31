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

Les package policies et l'objet `data-fleet` sont conservés pour le bootstrap
et la gestion de la plateforme. Ils ne constituent pas le chemin de télémétrie
des VM v2. Chaque VM active exécute EDOT Collector en mode agent et publie de
l'OTLP directement dans Kafka ; le Collector EDOT Kubernetes consomme ces
topics et exporte vers Elasticsearch.

Appliquer `make kibana-fleet-config-deploy` (inclus dans `make elk-deploy`) pour
préconfigurer Fleet sur un nouveau Kibana. `make fleet-sync` gère les éléments
de compatibilité encore nécessaires au POC ; la collecte active des VM reste
déclarée dans Ansible et `otel-agent.yml.j2`. Le flux OTel des applications,
de Kubernetes et des VM est distinct des éventuels objets Fleet historiques.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
