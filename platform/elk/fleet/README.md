# Policies Fleet et Elastic Agent

Ces fichiers JSON décrivent les intégrations Fleet synchronisées vers Kibana.
Ils ne contiennent pas de secret : les identifiants sont chargés à l'exécution.

## Parcours de lecture

- [`MONGODB.md`](MONGODB.md) : fonctionnement et adaptation de la policy
  `mongodb-fleet`.
- [`KAFKA.md`](KAFKA.md) : fonctionnement et adaptation de la policy
  `kafka-fleet` et de Jolokia.
- `mongodb-package-policy.json` : définition machine de la policy MongoDB.
- `kafka-package-policy.json` : définition machine de la policy Kafka.
- `kafka-topic-ingest-pipeline.json` : enrichissement du data stream Kafka.
- `system-package-policy.json` : exemple de policy système conservé comme
  référence ; elle n'est pas synchronisée par le script actuel.
- `elastic-agent.yml` : exemple de configuration standalone, distinct de Fleet.

Les deux package policies sont associées à l'agent policy `mongodb-hosts`. Dans
ce POC, un Elastic Agent tourne sur chaque VM : `localhost` désigne donc le
service local à la VM, jamais le poste qui exécute `make fleet-sync`.

Lancer `make fleet-sync` après avoir chargé les identifiants. Le script appelle
l'API Fleet pour créer ou mettre à jour les package policies, puis l'API
Elasticsearch pour les pipelines `@custom`. Il est idempotent, mais une mise à
jour de version de package doit toujours être vérifiée dans Kibana > Fleet.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
