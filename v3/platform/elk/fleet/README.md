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

Les package policies et l'objet `data-fleet` constituent le chemin actif de
télémétrie des VM v3. Chaque VM active exécute un Elastic Agent enrôlé dans
Fleet ; il collecte les logs et métriques puis exporte directement vers
Elasticsearch. Kafka et MongoDB sont observés par les intégrations de cette
policy, mais Kafka ne tamponne pas la télémétrie.

Appliquer `make kibana-fleet-config-deploy` (inclus dans `make elk-deploy`) pour
préconfigurer Fleet sur un nouveau Kibana, puis `make fleet-vms-provision` pour
créer un jeton temporaire et enrôler la VM. Le flux OTel des applications et
de Kubernetes reste déclaré dans `otel-kafka.yaml` ; le flux VM est déclaré
par la policy Fleet.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
