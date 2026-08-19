# Scripts ELK

Ces scripts pilotent les API Elasticsearch et Kibana depuis le poste hôte. Ils
ne stockent aucun mot de passe dans le dépôt.

## Lire et exécuter

1. `load-credentials.sh` lit les secrets ECK et exporte les variables utiles.
   Il doit être *sourcé* : `source ./platform/elk/scripts/load-credentials.sh`.
2. `sync-fleet-policies.sh` pousse les pipelines Kafka `@custom` et crée de
   façon idempotente la package policy PostgreSQL dans la policy Fleet existante.
3. `deploy-kibana-dashboard.sh` importe un export NDJSON dans Kibana.

Les valeurs `KIBANA_URL`, `ELASTICSEARCH_URL` et les options `--resolve` sont
paramétrables par variables d'environnement pour adapter l'accès au cluster.

## Documentation externe

- [API Elasticsearch](https://www.elastic.co/docs/api/doc/elasticsearch)
- [API Fleet](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-fleet)
- [API Saved Objects Kibana](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-saved-objects)
