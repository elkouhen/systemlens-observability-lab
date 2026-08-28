# Scripts ELK

Ces scripts pilotent les API Elasticsearch et Kibana depuis le poste hôte. Ils
ne stockent aucun mot de passe dans le dépôt.

## Lire et exécuter

1. `load-credentials.sh` lit les secrets ECK et le Secret
   `h0tl-supermarche-app/postgresql-credentials`, puis exporte les variables
   utiles. Une valeur `POSTGRESQL_PASSWORD` déjà présente reste prioritaire.
   Il doit être *sourcé* : `source ./platform/elk/scripts/load-credentials.sh`.
2. `sync-fleet-policies.sh` pousse les pipelines `@custom` et met à jour la
   policy PostgreSQL Fleet existante afin qu'elle ne s'exécute que sur
   `data-01`.
3. `delete-kibana-dashboard.sh` supprime les objets sauvegardés du dashboard
   MongoDB retiré.
4. `verify-dashboard-data.sh` contrôle la présence récente des jeux de données
   qui alimentent les dashboards System, Kubernetes, Kafka, MongoDB,
   PostgreSQL et APM. Lancer `make dashboards-verify` plutôt que le script
directement : la cible lit le secret ECK sans l'afficher.
5. `apply-apm-kibana-role.sh` crée ou met à jour un compte Kibana natif en
   lecture seule (`viewer`) et le Secret utilisé par `kibanaRef`. Les
   identifiants et le certificat CA restent hors Git.

Les valeurs `KIBANA_URL`, `ELASTICSEARCH_URL` et les options `--resolve` sont
paramétrables par variables d'environnement pour adapter l'accès au cluster.

## Documentation externe

- [API Elasticsearch](https://www.elastic.co/docs/api/doc/elasticsearch)
- [API Fleet](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-fleet)
- [API Saved Objects Kibana](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-saved-objects)
