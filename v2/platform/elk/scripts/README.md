# Scripts ELK

Ces scripts pilotent les API Elasticsearch et Kibana depuis le poste hôte. Ils
ne stockent aucun mot de passe dans le dépôt.

## Lire et exécuter

1. `load-credentials.sh` lit le secret ECK Elasticsearch et le Secret
   `h0tl-supermarche-app-v2/postgresql-credentials`, puis exporte les variables
   utiles. Une valeur `POSTGRESQL_PASSWORD` déjà présente reste prioritaire.
   En v2, aucun Secret APM n'est requis : les applications utilisent
   OpenTelemetry et le Gateway EDOT. Le script doit être *sourcé* :
   `source ./platform/elk/scripts/load-credentials.sh`.
2. `sync-fleet-policies.sh` pousse les pipelines `@custom` et applique les
   correctifs de compatibilité encore nécessaires au POC. Il ne configure pas
   le chemin actif de télémétrie EDOT, qui est déclaré dans Ansible et dans les
   manifests du Collector Kubernetes.
3. `verify-dashboard-data.sh` contrôle la présence récente des jeux de données
   qui alimentent les dashboards System, Kubernetes, Kafka, MongoDB,
   PostgreSQL et APM. Lancer `make dashboards-verify` plutôt que le script
   directement : la cible lit le secret ECK sans l'afficher.
4. `apply-apm-kibana-role.sh` crée ou met à jour un compte Kibana natif en
   lecture seule (`viewer`) et le Secret utilisé par `kibanaRef`. Les
   identifiants et le certificat CA restent hors Git.

Les valeurs `KIBANA_URL`, `ELASTICSEARCH_URL` et les options `--resolve` sont
paramétrables par variables d'environnement pour adapter l'accès au cluster.

## Documentation externe

- [API Elasticsearch](https://www.elastic.co/docs/api/doc/elasticsearch)
- [API Fleet](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-fleet)
- [API Saved Objects Kibana](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-saved-objects)
