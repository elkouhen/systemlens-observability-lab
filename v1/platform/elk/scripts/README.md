# Scripts ELK

Ces scripts pilotent les API Elasticsearch et Kibana depuis le poste hôte. Ils
ne stockent aucun mot de passe dans le dépôt.

## Lire et exécuter

1. `load-credentials.sh` lit les secrets ECK et le Secret
   `h0tl-supermarche-app/postgresql-credentials`, puis exporte les variables
   utiles. Une valeur `POSTGRESQL_PASSWORD` déjà présente reste prioritaire.
   Il doit être *sourcé* : `source ./platform/elk/scripts/load-credentials.sh`.
   Avant la première installation, les secrets ECK n'existent pas encore : le
   script affiche un avertissement et retourne avec succès. Le mot de passe
   PostgreSQL doit alors être fourni dans l'environnement avant `make deploy`.
2. `sync-fleet-policies.sh` pousse les pipelines `@custom`, réaffecte les
   Agents actifs à `data-fleet`, applique le correctif Kafka Raft et met à jour
   la policy PostgreSQL afin qu'elle ne s'exécute que sur `data-01`.
3. `verify-dashboard-data.sh` contrôle la présence récente des jeux de données
   qui alimentent les dashboards System, Kubernetes, Kafka, MongoDB,
   PostgreSQL et APM. Lancer `make dashboards-verify` plutôt que le script
   directement : la cible lit le secret ECK sans l'afficher.
4. `apply-apm-kibana-role.sh` crée ou met à jour un compte Kibana natif en
   lecture seule (`viewer`) et le Secret utilisé par `kibanaRef`. Les
   identifiants et le certificat CA restent hors Git.

La cible `make apm-logstash-credentials-apply` vérifie la clé API persistée
contre Elasticsearch. Si le cluster a été recréé et que la clé est devenue
invalide, elle en crée automatiquement une nouvelle et redémarre Logstash. Le
Secret contient la forme brute `id:api_key` ; Logstash encode cette valeur lui-
même pour l'en-tête `Authorization: ApiKey`.

Lors de `make deploy`, la clé Elasticsearch est préparée après la disponibilité
du cluster et transmise au premier `vagrant up`. Une clé d'enrôlement Fleet est
ensuite créée par `provision-fleet-vms.sh` via Kibana pour enrôler les VM dans
`data-fleet`.

Les valeurs `KIBANA_URL`, `ELASTICSEARCH_URL` et les options `--resolve` sont
paramétrables par variables d'environnement pour adapter l'accès au cluster.

## Documentation externe

- [API Elasticsearch](https://www.elastic.co/docs/api/doc/elasticsearch)
- [API Fleet](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-fleet)
- [API Saved Objects Kibana](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-saved-objects)
