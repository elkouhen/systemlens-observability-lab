# Kafka dans Fleet

Ce guide explique la package policy Kafka déclarée dans
[`../../kubernetes/base/observability/kibana.yaml`](../../kubernetes/base/observability/kibana.yaml)
et le pipeline [`kafka-topic-ingest-pipeline.json`](kafka-topic-ingest-pipeline.json).
La policy Kafka est déclarée dans `kibana.yaml`; `make fleet-sync` applique les
pipelines Elasticsearch `@custom`. Chaque hôte de
données héberge un broker/controller Kafka KRaft dans Podman. Toutes les VM
actives exécutent l'EDOT Collector en mode agent.

## Chemin de collecte v2

```text
EDOT Agent de chaque VM
  └─ kafka_metrics : localhost:9092
       └─ brokers, topics, partitions, consumer groups
            ↓
       edot-vm-metrics → Kafka → EDOT Collector → Elasticsearch
```

Le receiver OTel couvre les métriques Kafka exposées par le protocole Kafka.
Les documents sont routés vers `metrics-kafka.otel-*` avec
`service.name: kafka` et `host.name: data-01`. Jolokia est historique et n'est
pas requis par le chemin v2.

## Lire la policy

1. La collecte des VM est assurée par EDOT Collector, pas par la policy
   `data-fleet`.
2. Les entrées `filelog/vm` et `hostmetrics` collectent respectivement les
   logs et métriques hôte. Aucun Filebeat, Metricbeat ou Logstash n'est utilisé.
3. `kafka_metrics` utilise `localhost:9092` toutes les 60 secondes et produit
   `kafka.brokers`, les offsets/partitions et les métriques de consumer groups.
4. Les métriques JVM détaillées nécessitent une instrumentation JMX dédiée ;
   elles ne sont pas promises par le receiver Kafka natif.

La configuration Kafka doit simplement rendre le broker joignable sur
`localhost:9092` depuis EDOT Agent.

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

Après une modification EDOT, exécuter `make vm-provision` puis vérifier le
service `poc-otel-agent` sur chaque VM et les data streams dans Discover.

## Vérification et dépannage

1. Vérifier depuis la VM EDOT que `localhost:9092` répond et que le
   quorum KRaft est sain : `make vm-status`.
2. Dans Discover, filtrer `data_stream.dataset: kafka.otel`.
3. Vérifier les métriques `kafka.brokers`, `kafka.partition.current_offset`
   et `kafka.consumer_group.lag`.
4. En cas d'échec EDOT, consulter `journalctl -u poc-otel-agent` et vérifier
   que les topics `edot-vm-logs` et `edot-vm-metrics` existent dans Kafka.

Le Deployment `otel-kafka-exporter` consomme les topics OTLP `edot-vm-logs` et
`edot-vm-metrics`, en plus des topics OTLP des applications et de Kubernetes.

## Documentation officielle

- [Intégration Kafka Elastic](https://www.elastic.co/docs/reference/integrations/kafka)
- [Créer ou mettre à jour une package policy Fleet](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-fleet-package-policies)
- [Pipelines d'ingestion Elasticsearch](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Documentation Apache Kafka KRaft](https://kafka.apache.org/documentation/#kraft)
