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

Les package policies et l'objet `data-fleet` restent versionnés pour les assets
Kibana et une éventuelle migration, mais ne constituent pas le chemin actif de
télémétrie des VM. Chaque VM active exécute un Elastic Agent EDOT standalone :
les receivers locaux collectent les métriques Kafka, MongoDB, PostgreSQL et
système ainsi que les logs, puis les envoient au Collecteur Edge.
Elasticsearch reçoit ensuite les signaux via Kafka et l'exporteur backend.

Appliquer `make kibana-fleet-config-deploy` (inclus dans `make elk-deploy`) pour
préconfigurer les assets Fleet sur un nouveau Kibana, puis
`make elastic-agent-vm-provision` pour déployer la configuration EDOT standalone
des VM. Le flux OTel des applications, de Kubernetes et des VM converge vers
les topics déclarés dans `otel-kafka.yaml` ; aucun enrôlement Fleet des VM n'est
requis.

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
