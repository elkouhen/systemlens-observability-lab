# Kafka dans Fleet

Ce guide explique la package policy Kafka déclarée dans
[`../../kubernetes/base/observability/kibana.yaml`](../../kubernetes/base/observability/kibana.yaml)
et le pipeline [`kafka-topic-ingest-pipeline.json`](kafka-topic-ingest-pipeline.json).
La policy Kafka est déclarée dans `kibana.yaml`; `make fleet-sync` applique les
pipelines Elasticsearch `@custom`. Chaque hôte de
données héberge un broker/controller Kafka KRaft dans Podman. Seuls `data-01`
et `data-02` exécutent un Elastic Agent enrôlé dans Fleet ; `data-03` utilise
Filebeat et Metricbeat.

## Deux chemins de collecte complémentaires

```text
Elastic Agent de la VM Elastic Agent
  ├─ protocole Kafka : localhost:9092
  │    └─ broker, partition, consumergroup
  └─ HTTP Jolokia : 127.0.0.1:8778/jolokia
       └─ controller, JVM, réseau, topics, Raft, réplication
            ↓
       metrics-kafka.*-default → pipelines @custom → Elasticsearch
```

Le port Kafka permet de collecter l'état fonctionnel du cluster. Jolokia expose
les MBeans JMX nécessaires aux métriques JVM et broker détaillées. Le bind sur
`127.0.0.1` est volontaire : Jolokia n'est pas publié sur le réseau privé.

## Lire la policy

1. La policy `data-01-02-fleet` rattache aussi Kafka à la VM Elastic Agent ; son
   nom historique ne limite pas son contenu à MongoDB.
2. Le bloc `logfile` est actif et constitue l'unique source des logs Kafka sur
   `data-01` et `data-02`. Ne pas y démarrer Filebeat en parallèle ; `data-03`
   est le profil Beats distinct.
3. `kafka/metrics` utilise `localhost:9092` toutes les 60 secondes et produit
   `kafka.broker`, `kafka.partition` et `kafka.consumergroup`.
4. `jolokia/metrics` utilise `http://127.0.0.1:8778/jolokia` et produit les
   streams `controller`, `jvm`, `network`, `log_manager`, `replica_manager`,
   `topic` et `raft`.

La configuration Kafka doit démarrer le broker avec l'agent JVM Jolokia. Sans
cet agent, les streams collectés par `jolokia/metrics` échoueront même si le
port Kafka `9092` répond correctement.

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

Après une modification de la policy, appliquer
`make kibana-fleet-config-deploy` et attendre le redémarrage piloté par ECK.
Lancer ensuite `make fleet-sync` pour mettre à jour les pipelines `@custom`.
Vérifier l'état de l'Agent dans Fleet et les data streams dans Discover.

## Vérification et dépannage

1. Vérifier depuis la VM Elastic Agent que `localhost:9092` répond et que le
   quorum KRaft est sain : `make vm-status`.
2. Vérifier que `http://127.0.0.1:8778/jolokia` répond localement. Une erreur
   ici indique un problème d'agent Jolokia ou de publication du port Podman.
3. Dans Discover, filtrer `data_stream.dataset: kafka.raft` puis
   `data_stream.dataset: kafka.broker`.
4. Vérifier que `service.address` contient le nom de l'hôte pour les datasets
   Jolokia ; sinon relancer `make fleet-sync` et contrôler les pipelines
   `metrics-kafka.*@custom`.
5. En cas d'échec Fleet, comparer la version de package demandée dans le JSON
   avec celle disponible dans Kibana avant de modifier les streams.

## Documentation officielle

- [Intégration Kafka Elastic](https://www.elastic.co/docs/reference/integrations/kafka)
- [Créer ou mettre à jour une package policy Fleet](https://www.elastic.co/docs/api/doc/kibana/group/endpoint-fleet-package-policies)
- [Pipelines d'ingestion Elasticsearch](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Documentation Apache Kafka KRaft](https://kafka.apache.org/documentation/#kraft)
