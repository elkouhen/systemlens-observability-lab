# Policies Fleet et Elastic Agent

Ces fichiers JSON décrivent les intégrations Fleet synchronisées vers Kibana.
Ils ne contiennent pas de secret : les identifiants sont chargés à l'exécution.

## Lire les fichiers

- `mongodb-package-policy.json` : métriques MongoDB de chaque VM.
- `kafka-package-policy.json` : métriques Kafka et Jolokia local.
- `kafka-topic-ingest-pipeline.json` : enrichissement du data stream Kafka.
- `system-package-policy.json` : exemple de policy système conservé comme
  référence ; elle n'est pas synchronisée par le script actuel.
- `elastic-agent.yml` : exemple de configuration standalone, distinct de Fleet.

Lancer `make fleet-sync` après avoir chargé les identifiants. Le script est
idempotent : il crée ou met à jour les policies et pipelines.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
