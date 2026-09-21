# Policies Fleet et Elastic Agent

La configuration Fleet de référence est déclarée dans
[`../scripts/bootstrap-fleet-policies.sh`](../scripts/bootstrap-fleet-policies.sh)
et appliquée au Kibana Quadlet de `elk-01` par l'API Fleet. Aucun composant
Kibana, Fleet Server ou ECK n'est déployé dans Kubernetes.

## Parcours de lecture

- [`MONGODB.md`](MONGODB.md) : fonctionnement de l'intégration MongoDB.
- [`KAFKA.md`](KAFKA.md) : fonctionnement de l'intégration Kafka et de
  Jolokia.
- [`ADR-001-choix-elastic-agent-otel.md`](../../../docs/ADR-001-choix-elastic-agent-otel.md) :
  choix de collecte par type de composant.
- `kafka-topic-ingest-pipeline.json` : enrichissement du data stream Kafka.

Les package policies et l'objet `data-fleet` constituent le chemin actif de
télémétrie des VM architecture. Chaque VM active exécute un Elastic Agent enrôlé dans
Fleet ; il collecte les logs et métriques puis exporte directement vers
Elasticsearch. Kafka et MongoDB sont observés par les intégrations de cette
policy, mais Kafka ne tamponne pas la télémétrie.

Appliquer `make kibana-fleet-config-deploy` (inclus dans `make elk-deploy`) pour
préconfigurer Fleet sur un nouveau Kibana, puis `make fleet-vms-provision` pour
créer un jeton temporaire et enrôler la VM. Le flux OTel des applications et
de Kubernetes reste déclaré dans `otel-kafka.yaml` ; le flux VM est déclaré
par la policy Fleet.

Le bootstrap utilise exclusivement l'API Fleet pour créer ou mettre à jour les
agent policies. Il migre automatiquement une ancienne policy
`eck-fleet-server` créée comme saved object sans `revision`, car cette forme
laisse Fleet Server bloqué en `STARTING`. Une erreur de lecture de Kibana est
bloquante : elle ne doit pas être interprétée comme une policy absente.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
