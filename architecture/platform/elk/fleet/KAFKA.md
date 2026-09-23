# Kafka avec l'agent EDOT standalone

Ce guide explique la package policy Kafka déclarée dans
[`../scripts/bootstrap-fleet-policies.sh`](../scripts/bootstrap-fleet-policies.sh)
et le pipeline [`kafka-topic-ingest-pipeline.json`](kafka-topic-ingest-pipeline.json).
La policy Kafka est conservée comme asset de compatibilité dans Kibana. La
collecte active est déclarée dans le template EDOT Ansible et déployée par
`make elastic-agent-vm-provision`. Chaque hôte de données héberge un
broker/controller Kafka KRaft dans Podman.

## Chemin de collecte architecture

```text
Elastic Agent EDOT standalone de poc-01
  └─ receiver kafka_metrics : localhost:9092
       └─ brokers, topics, partitions, consumer groups
            ↓
       métriques Kafka → Elasticsearch
```

Le receiver `kafka_metrics` active les scrapers `brokers`, `topics` et
`consumers`. Les documents sont routés vers
`metrics-kafkametricsreceiver.otel-default`; les métriques principales sont
`kafka.brokers`, `kafka.topic.partitions` et `kafka.consumer_group.lag`.
Jolokia est historique et n'est pas requis par le chemin architecture.

## Lire la policy

1. La collecte est assurée par l'agent EDOT standalone de `poc-01`.
2. Le receiver `filelog/system` collecte les logs locaux et le receiver
   `hostmetrics/system` les métriques hôte.
3. Le receiver Kafka utilise `localhost:9092` toutes les 60 secondes et produit
   `kafka.brokers`, les offsets/partitions et les métriques de consumer groups.
4. Les métriques JVM détaillées nécessitent une instrumentation JMX dédiée ;
   elles ne sont pas promises par le receiver Kafka natif.

La configuration Kafka doit simplement rendre le broker joignable sur
`localhost:9092` depuis l'Elastic Agent.

## Pipelines personnalisés

L'endpoint Jolokia est local, ce qui donnerait sinon une identité ambiguë à
`service.address`. `sync-fleet-policies.sh` installe un pipeline `@custom` pour
chaque dataset Jolokia afin de remplacer cette valeur par `host.name`. Le
pipeline `metrics-kafka.topic@custom` est versionné dans ce dossier ; les
autres pipelines sont construits idempotemment par le script.

Cette convention permet aux vues Kibana de regrouper les métriques par broker,
plutôt que de montrer trois fois `127.0.0.1:8778`.

## Adapter à un autre environnement

| Besoin | Modification à faire |
| --- | --- |
| Agent hors du broker | remplacer `localhost:9092` par les bootstrap servers accessibles |
| Jolokia distant | modifier `jolokia_hosts`, activer TLS/authentification et limiter l'accès réseau |
| Intervalle de collecte | changer `period` global Kafka et/ou celui de chaque stream Jolokia |
| Désactiver une famille coûteuse | passer le stream concerné à `enabled: false` |
| Kafka sans Jolokia | conserver broker/partition/consumergroup et désactiver les streams JMX |
| Topics très nombreux | surveiller le volume du stream `kafka.topic` et ajuster l'intervalle avant d'augmenter la capacité |

Après une modification de policy, exécuter `make fleet-sync` puis vérifier
`systemctl is-active elastic-agent` sur chaque VM et les data streams dans Discover.

## Vérification et dépannage

1. Vérifier depuis la VM que `localhost:9092` répond et que le
   quorum KRaft est sain : `make vm-status`.
2. Dans Discover, filtrer `data_stream.dataset: kafkametricsreceiver.otel`.
3. Vérifier les métriques `kafka.brokers`, `kafka.partition.current_offset`
   et `kafka.consumer_group.lag`.
4. En cas d'échec Fleet, consulter `journalctl -u elastic-agent` et vérifier
que l'agent apparaît comme healthy dans Fleet.

Le service `observability-otel-kafka-exporter` sur `otel-backend-01` consomme les
topics OTLP `otel-traces`, `otel-metrics` et `otel-logs` pour les applications
et Kubernetes uniquement.

## Documentation officielle

- [Intégration Kafka Elastic](https://www.elastic.co/docs/reference/integrations/kafka)
- [Assets Kafka OpenTelemetry](https://www.elastic.co/docs/reference/integrations/kafka_otel)
- [Créer ou mettre à jour une package policy Fleet](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-fleet-package-policies)
- [Pipelines d'ingestion Elasticsearch](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Documentation Apache Kafka KRaft](https://kafka.apache.org/documentation/#kraft)
