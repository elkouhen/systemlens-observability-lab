# Policies Fleet et Elastic Agent

La configuration Fleet de référence est déclarée dans le template Kibana
[`../../../ansible/roles/elk/templates/kibana.yml.j2`](../../../ansible/roles/elk/templates/kibana.yml.j2)
avec `xpack.fleet.packages` et `xpack.fleet.agentPolicies`. Le script
[`../scripts/bootstrap-fleet-policies.sh`](../scripts/bootstrap-fleet-policies.sh)
ne conserve que les opérations dynamiques. Aucun composant
Kibana, Fleet Server ou ECK n'est déployé dans Kubernetes.

## Parcours de lecture

- [`MONGODB.md`](MONGODB.md) : fonctionnement de l'intégration MongoDB.
- [`KAFKA.md`](KAFKA.md) : fonctionnement de l'intégration Kafka et de
  Jolokia.
- La collecte PostgreSQL OTel et les droits de supervision sont déclarés dans
  le rôle Ansible `poc` et dans le template EDOT de l'agent.
- [`ADR-001-choix-elastic-agent-otel.md`](../../../docs/ADR-001-choix-elastic-agent-otel.md) :
  choix du plan de données OTLP et de la gateway.
- `kafka-topic-ingest-pipeline.json` : enrichissement du data stream Kafka.

Les packages `*_otel` fournissent les assets Kibana. Les package policies
classiques `kafka`, `mongodb` et `postgresql` restent versionnées pour la
compatibilité et une éventuelle migration, mais ne doivent pas être assignées
aux agents EDOT standalone. Elles ne constituent pas le chemin actif de
télémétrie des VM. Chaque VM active exécute un Elastic Agent EDOT standalone :
les receivers locaux collectent les métriques Kafka, MongoDB, PostgreSQL et
système ainsi que les logs, puis les envoient au Collecteur Edge.
Elasticsearch reçoit ensuite les signaux via Kafka et l'exporteur backend.

Appliquer `make fleet-assets-deploy` (inclus dans `make elk-deploy`) pour
installer les packages `system_otel` `0.3.0`, `kubernetes_otel` `2.6.0`,
`kafka_otel` `0.3.1`, `postgresql_otel` `0.5.0`, `mongodb_otel` `0.3.1` et
`otel_collector_internal_telemetry` `1.2.3`,
compatibles avec Kibana `9.4.3`, puis préconfigurer les assets Fleet sur un
nouveau Kibana. Utiliser ensuite `make fleet-opamp-enable` pour activer le
monitoring OpAMP des VM sans modifier la configuration EDOT standalone. OpAMP
remonte l’état et la télémétrie interne des agents ; les templates Ansible
restent la source de vérité de leur configuration. Le flux OTel des applications, de Kubernetes
et des VM converge vers les topics déclarés dans `otel-kafka.yaml`. Les VM ne
sont pas enrôlées comme agents Fleet classiques afin de conserver l'export OTLP
vers `otel-edge-01`.

La cible `fleet-prerequisites` vérifie les credentials Elasticsearch, l’API
Kibana et un Fleet Server `HEALTHY`. La cible `kibana-fleet-config-deploy`
vérifie d’abord l’accès de `elk-01` à `epr.elastic.co`, amorce la policy native
`eck-fleet-server` avec Elasticsearch et Kibana disponibles, installe les
packages Fleet, puis démarre Fleet Server et attend son état `HEALTHY`. Cette
séquence évite de démarrer Fleet Server tant que sa policy ne contient pas
l’intégration Fleet Server. La cible
`fleet-opamp-enable` échoue si les quatre agents VM ne sont pas `online` dans
Fleet. Une exécution réussie constitue la preuve du plan de contrôle, sans
réinstaller `elk-01`.

Les agents EDOT standalone et les collecteurs EDOT des VM exportent leur
télémétrie interne par OTLP vers un receiver local, puis la routent dans le
dataset `collectortelemetry`. Le flux comprend les métriques, logs et traces
internes. Les agents et Edge envoient ces signaux vers Kafka ; le backend les
écrit dans Elasticsearch. Fleet peut ainsi afficher les colonnes CPU et
mémoire des agents OpAMP dans `Fleet > Agents`, tandis que les dashboards
dédiés suivent les erreurs et la performance des pipelines. Les traces
internes restent conditionnées à la production effective de spans par la
distribution du Collector. Cette télémétrie est distincte du flux de données
métier envoyé vers `otel-edge-01`.

Kibana préconfigure les agent policies et les package policies à son démarrage.
Le bootstrap installe les packages manquants, crée les package policies MongoDB,
Kafka et PostgreSQL sous `data-fleet` si Kibana ne les a pas créées, injecte le
mot de passe PostgreSQL dans la package policy et crée les clés d'enrôlement
Fleet Server.
Une erreur de lecture de Kibana est bloquante : elle ne doit pas être interprétée
comme une policy absente.

## Documentation externe

- [Fleet et Elastic Agent](https://www.elastic.co/docs/reference/fleet)
- [Créer des ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Intégration MongoDB](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Intégration Kafka](https://www.elastic.co/docs/reference/integrations/kafka)
- [Assets Kafka OpenTelemetry](https://www.elastic.co/docs/reference/integrations/kafka_otel)
- [Assets PostgreSQL OpenTelemetry](https://www.elastic.co/docs/reference/integrations/postgresql_otel)
