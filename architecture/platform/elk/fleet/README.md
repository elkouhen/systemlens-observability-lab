# Policies Fleet et Elastic Agent

La configuration Fleet de référence est déclarée dans
[`../scripts/bootstrap-fleet-policies.sh`](../scripts/bootstrap-fleet-policies.sh)
et appliquée au Kibana Quadlet de `elk-01` par l'API Fleet. Aucun composant
Kibana, Fleet Server ou ECK n'est déployé dans Kubernetes.

## Parcours de lecture

- [`MONGODB.md`](MONGODB.md) : fonctionnement de l'intégration MongoDB.
- [`KAFKA.md`](KAFKA.md) : fonctionnement de l'intégration Kafka et de
  Jolokia.
- La collecte PostgreSQL OTel et les droits de supervision sont déclarés dans
  le rôle Ansible `poc` et dans le template EDOT de l'agent.
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
installer les packages `system_otel` `0.3.0`, `kubernetes_otel` `2.6.0`,
`kafka_otel` `0.3.1`, `postgresql_otel` `0.5.0` et `mongodb_otel` `0.3.1`,
compatibles avec Kibana `9.4.3`, puis préconfigurer les
assets Fleet sur un nouveau Kibana, puis
`make fleet-vm-monitoring` pour activer le monitoring OpAMP des VM sans modifier
la configuration EDOT standalone. Le flux OTel des applications, de Kubernetes
et des VM converge vers les topics déclarés dans `otel-kafka.yaml`. Les VM ne
sont pas enrôlées comme agents Fleet classiques afin de conserver l'export OTLP
vers `otel-edge-01`.

La cible attend d'abord un Fleet Server `HEALTHY`, puis échoue si les quatre
agents VM ne sont pas `online` dans Fleet. Une exécution réussie constitue donc
la preuve de réconciliation du plan de contrôle.

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
- [Assets Kafka OpenTelemetry](https://www.elastic.co/docs/reference/integrations/kafka_otel)
- [Assets PostgreSQL OpenTelemetry](https://www.elastic.co/docs/reference/integrations/postgresql_otel)
