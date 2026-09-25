# Scripts ELK

Ces scripts pilotent les API Elasticsearch et Kibana depuis le poste hôte. Ils
ne stockent aucun mot de passe dans le dépôt.

## Lire et exécuter

1. `load-credentials.sh` lit le secret ECK Elasticsearch et le Secret
   `h0tl-supermarche-app/postgresql-credentials`, puis exporte les variables
   utiles. Une valeur `POSTGRESQL_PASSWORD` déjà présente reste prioritaire.
   La clé API Elasticsearch déjà exportée est vérifiée contre le cluster ; si
   elle appartient à un ancien cluster, elle est automatiquement remplacée.
   En architecture, aucun Secret APM n'est requis : les applications utilisent
   OpenTelemetry et le Collecteur EDOT Edge. Le script doit être *sourcé* :
   `source ./platform/elk/scripts/load-credentials.sh`.
   Le template Kibana préconfigure les packages Fleet et les package policies ;
   `bootstrap-fleet-policies.sh` vérifie leur installation et réconcilie le
   secret PostgreSQL dynamique. Les packages `kubernetes_otel` `2.6.0`,
   `kafka_otel` `0.3.1`, `postgresql_otel` `0.5.0` et `mongodb_otel` `0.3.1`
   fournissent les assets Kibana des dashboards OTel correspondants.
   Les Collectors restent autonomes et ne sont pas enrôlés comme agents Fleet.
   `reconcile-kafka-otel-dashboard.sh` réconcilie le panneau de comptage des
   brokers après l'installation du package `kafka_otel`.
2. `sync-fleet-policies.sh` pousse les pipelines `@custom` et applique les
   correctifs de compatibilité encore nécessaires au POC. Il ne configure pas
   le chemin actif de télémétrie EDOT, qui est déclaré dans Ansible et dans les
   manifests du Collector Kubernetes.
   Les collecteurs EDOT Kubernetes ne sont pas enrôlés dans Fleet et ne
   nécessitent donc aucune clé OpAMP ; leur configuration est portée par les
   ConfigMaps Kustomize.
3. `verify-dashboard-data.sh` contrôle la présence récente des jeux de données
   qui alimentent les dashboards System, Kubernetes, Kafka, MongoDB,
   PostgreSQL et APM. Lancer `make dashboards-verify` plutôt que le script
   directement : la cible lit le secret ECK sans l'afficher. Les intégrations
   Fleet utilisent les datasets natifs `kafka.broker`, `kafka.partition`,
   `kafka.consumergroup`, `mongodb.status`, `mongodb.metrics`,
   `mongodb.dbstats` et `postgresql.database` ; les champs contrôlés restent
   ceux des intégrations (`kafka.*`, `mongodb.*` et `postgresql.*`).
   `verify-kubernetes-otel-dashboards.sh` contrôle les références des dashboards
   Kubernetes OTel aux champs réellement produits par les Collectors OTel.
   `verify-dashboard-data.sh` contrôle également l’ensemble des métriques
   PostgreSQL utilisées par les sept dashboards et liste explicitement les
   métriques KO lorsqu’une source n’est plus alimentée.
   `verify-postgresql-otel-dashboards.sh` contrôle le mapping, la présence
   récente des métriques PostgreSQL, les références ES|QL et la cohérence des
   colonnes Lens avec les résultats. Utiliser
   `make postgresql-otel-dashboards-verify` pour l’exécuter séparément.
4. `apply-apm-kibana-role.sh` crée ou met à jour un compte Kibana natif en
   lecture seule (`viewer`) et le Secret utilisé par `kibanaRef`. Les
   identifiants et le certificat CA restent hors Git.
5. `sync-observability-policies.sh` réconcilie les SLO et règles d'alerte
   versionnés. Il retire `id` du corps lors de la mise à jour d'un SLO. Pour les
   règles, il conserve `rule_type_id` et `consumer` à la création et les retire
   du corps des mises à jour, conformément aux schémas Kibana. Utiliser `make
   observability-policies-deploy` : la cible lit le secret ECK sans l'afficher.

Les valeurs `KIBANA_URL`, `ELASTICSEARCH_URL` et les options `--resolve` sont
paramétrables par variables d'environnement pour adapter l'accès au cluster.

## Documentation externe

- [API Elasticsearch](https://www.elastic.co/docs/api/doc/elasticsearch)
- [API Fleet](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-fleet)
- [API Saved Objects Kibana](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-saved-objects)

`retention.py` lit la déclaration `../ilm/retention.json`, réconcilie les
politiques ILM et les composants `logs@custom`, `metrics@custom`, `traces@custom`,
puis migre les indices existants. Il préserve les autres paramètres des
composants et vérifie les templates résolus. Utiliser `make retention-plan`,
`make ilm-deploy` et `make retention-verify` ; voir le
[guide de rétention](../retention/README.md).

`verify-observability-contracts.sh` contrôle deux contrats sur une fenêtre
temporelle récente. Le mode `trace-context` vérifie les propagateurs W3C,
cherche un même `trace.id` sur `order-service`, `inventory-service` et un span
Kafka, puis vérifie la présence d’un log corrélé. Le mode `schema` vérifie
`@timestamp`, `data_stream.dataset`, `service.name`, les identifiants de span
et `ecs.version` sur les flux applicatifs. Les deux modes exigent
`ELASTICSEARCH_PASSWORD` et acceptent `OBSERVABILITY_VERIFY_WINDOW`.

Depuis la racine du dépôt, exécuter :

```bash
make trace-context-verify
make observability-schema-verify
```

Ces contrôles nécessitent des données récentes. Générer une commande avec
`make order-service-command` avant le contrôle de propagation si aucun flux
applicatif n’a été produit dans la fenêtre choisie.
