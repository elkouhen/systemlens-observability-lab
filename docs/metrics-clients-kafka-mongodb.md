# Instrumenter les clients Kafka et MongoDB

Ce guide décrit les consignes à appliquer dans une application Java/Spring
pour exposer les métriques de ses clients Kafka et MongoDB à Elastic. Il ne
couvre pas les métriques des brokers Kafka ni celles des serveurs MongoDB.

## Chaîne de collecte

```text
client Kafka/MongoDB
    → Micrometer
    → Spring Boot Actuator
    → /actuator/prometheus
    → Elastic Agent Prometheus
    → Elasticsearch
    → Kibana
```

Le dataset applicatif doit rester distinct des datasets APM natifs. Dans ce
POC, les métriques sont envoyées vers un data stream de la forme
`metrics-app.prometheus.<plateforme>-<environnement>`.

## Kafka côté client

### Métriques à activer

Les vrais `Producer` et `Consumer` Kafka doivent être liés au
`MeterRegistry`. Les métriques de configuration seules, comme `linger.ms` et
`batch.size`, ne suffisent pas.

Le périmètre recommandé couvre notamment :

- débit et erreurs : `record-send-rate`, `record-error-rate`,
  `record-retry-rate`, `records-consumed-rate` et `bytes-consumed-rate` ;
- batching : taille moyenne et maximale des batches, ratio de compression,
  nombre moyen de records par requête ;
- latence : latence des requêtes Produce et Fetch, commits et rebalances ;
- saturation : buffer disponible, attente du buffer, connexions et throttling ;
- consommation : lag maximal, heartbeats, polling et partitions assignées.

Spring Kafka fournit `MicrometerProducerListener` et
`MicrometerConsumerListener` pour gérer automatiquement le binding des
clients créés par les factories. Les timers `spring.kafka.template` et
`spring.kafka.listener` complètent les métriques natives du client Kafka.

Documentation :

- [Micrometer — Apache Kafka](https://docs.micrometer.io/micrometer/reference/reference/kafka.html)
- [Spring Kafka — métriques Micrometer](https://docs.spring.io/spring-kafka/reference/kafka/micrometer.html)
- [Spring Kafka — observations](https://docs.spring.io/spring-kafka/reference/appendix/micrometer.html)

### Interprétation de `linger.ms` et `batch.size`

Ces deux valeurs sont des paramètres du Producer :

- `linger.ms` est le délai maximal d'attente avant l'envoi d'un batch
  incomplet ;
- `batch.size` est la taille maximale du batch par partition.

Les métriques `batch-size-avg` et `batch-size-max` mesurent le résultat réel
des envois. Elles ne remplacent pas les valeurs de configuration.

## MongoDB côté client

### Commandes MongoDB

Le client MongoDB doit enregistrer un `MongoMetricsCommandListener` auprès du
`MongoClientSettings`. Les métriques doivent au minimum distinguer :

- le nom de la commande (`find`, `insert`, `update`, `delete`, `aggregate`) ;
- le nombre d'appels ;
- la durée et les erreurs ;
- l'adresse du serveur lorsque cette dimension est nécessaire au diagnostic.

```java
MongoClientSettings settings = MongoClientSettings.builder()
        .addCommandListener(new MongoMetricsCommandListener(meterRegistry))
        .build();
```

Pour les métriques du pool de connexions, utiliser un
`ConnectionPoolListener` du driver MongoDB et l'exposer via un binder
Micrometer dédié si les indicateurs de pool sont nécessaires : taille du
pool, connexions utilisées, attente d'emprunt, connexions créées et fermées.

Documentation :

- [Micrometer — MongoDB](https://docs.micrometer.io/micrometer/reference/reference/mongodb.html)
- [MongoDB Java Driver — monitoring](https://www.mongodb.com/docs/drivers/java/sync/current/logging-monitoring/monitoring/)

## Exposition Actuator

Le cas d'usage de réservation expose également la métrique métier
`business.orders.completed`. Elle est incrémentée après les écritures MongoDB et
PostgreSQL réussies, avec le tag de faible cardinalité `channel` (`rest` ou
`kafka`). En v3, le Gateway scrappe cette métrique via `/actuator/prometheus`.

Le flux de réassort expose deux compteurs complémentaires :
`business.stock.restock.requested` pour les demandes émises par
`restock-service`, et `business.stock.restock.completed` pour les demandes
appliquées avec succès par `inventory-service`. Ils permettent de comparer les
réassorts demandés et effectivement réalisés.

L'application doit exposer uniquement les endpoints utiles :

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
```

Vérifier localement :

```bash
curl --fail --silent http://localhost:8080/actuator/prometheus \
  | grep -E 'kafka_|spring_kafka|mongodb_|mongo_'
```

Le Service Kubernetes utilisé par l'Elastic Agent doit cibler le port HTTP
de l'application. Le scrape doit être exécuté à intervalle régulier, par
exemple toutes les 15 secondes.

## Elastic Agent et Kibana

L'Elastic Agent utilise l'intégration Prometheus pour appeler
`/actuator/prometheus`. Il doit ajouter au minimum :

- `service.name` ;
- l'environnement de déploiement ;
- le dataset et le namespace du data stream convenus par la plateforme.

Dans Kibana Discover, filtrer par exemple :

```kql
data_stream.type: metrics
and data_stream.dataset: "app.prometheus.*"
and service.name: "inventory-service"
```

Les métriques sont stockées sous `prometheus.metrics.*` pour la collecte Elastic
Agent. Pour la collecte Prometheus du Gateway v3, elles sont disponibles dans
le data stream `metrics-prometheusreceiver.otel-*`, sous `metrics.*`.
Elles sont consultables dans Discover et dans les dashboards métriques, pas
uniquement dans l'interface APM.

Dans Kibana Discover, sélectionner `metrics-prometheusreceiver.otel-*` et
utiliser le filtre :

```kql
data_stream.dataset: "prometheusreceiver.otel"
and resource.attributes.service.name: "supermarket-applications"
and metrics.business_orders_completed_total: *
```

Pour visualiser les réassorts appliqués par `inventory-service` :

```kql
data_stream.dataset: "prometheusreceiver.otel"
and resource.attributes.server.address: "inventory-service.h0tl-supermarche-app.svc.cluster.local"
and metrics.business_stock_restock_completed_total: *
```

La valeur est un compteur cumulatif par instance. Pour une série temporelle,
utiliser `metrics.business_orders_completed_total` avec `attributes.channel`
comme dimension et calculer un taux ou une variation selon le besoin.

## Cardinalité et sécurité

À conserver dans les tags :

- `service.name` ;
- environnement ;
- `client.id` ;
- topic Kafka ;
- commande MongoDB ;
- collection MongoDB si son nombre reste maîtrisé.

À ne pas utiliser comme tags :

- clé ou valeur d'un message Kafka ;
- identifiant de document MongoDB ;
- requête complète ;
- exception contenant des données métier ;
- identifiant de corrélation non borné.

Les secrets Kafka et MongoDB ne doivent jamais être exportés comme labels ou
champs de métriques. Les URI et identifiants restent injectés par Secret ou
variable d'environnement.

## Points de vérification

1. Le client Kafka réel est lié au `MeterRegistry`.
2. Le `MongoClient` utilise le listener de commandes prévu.
3. `/actuator/prometheus` retourne des métriques Kafka et MongoDB.
4. L'Elastic Agent atteint le Service Kubernetes de l'application.
5. Elasticsearch reçoit des documents dans le data stream applicatif.
6. Kibana utilise une fenêtre temporelle adaptée et le data view couvre
   `metrics-app.prometheus.*`.
7. Les métriques ne contiennent pas de tags à forte cardinalité.

Une absence de métrique dans Kibana doit être diagnostiquée dans cet ordre :
endpoint Actuator, scrape Elastic Agent, sortie d'ingestion, data stream,
data view et fenêtre temporelle.
