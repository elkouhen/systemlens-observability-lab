# Briques de remontée de la télémétrie

Ce document est la référence commune pour comprendre la remontée des logs,
des traces et des métriques dans les architectures v1, v2 et v3 du POC. Il
décrit chaque brique avec la même grille : rôle, entrées, sorties et gestion
de la pression.

Les réglages indiqués comme actifs sont ceux présents dans le dépôt. Une règle
indiquée comme « à prévoir » n'est pas encore configurée.

## 1. Conventions communes

| Signal | Événement | Identifiants à préserver |
| --- | --- | --- |
| Logs | Ligne stdout, fichier ou journald | `service.name`, `service.version`, `trace.id`, `span.id`, `data_stream.*` |
| Traces | Transaction et spans | `trace.id`, `span.id`, service, environnement |
| Métriques | Point de mesure ou série | nom, valeur, labels, service/hôte, `data_stream.*` |

| Mécanisme | Effet | Limite |
| --- | --- | --- |
| Rate limit | Plafond en requêtes, événements ou octets par seconde | Ne réduit pas un événement déjà accepté |
| Sampling | Réduit les traces conservées | Ne limite pas logs et métriques |
| Filtrage | Écarte des événements ou dimensions | Ne remplace pas une protection mémoire |
| Batch | Regroupe avant émission | Ne réduit pas le volume total |
| Backpressure | Ralentit le producteur quand l'aval est saturé | Augmente potentiellement la latence |
| Queue/buffer | Absorbe un pic ou une panne courte | Ne constitue pas un plafond |
| `memory_limiter` | Protège un Collector contre l'épuisement mémoire | Ne protège pas directement Elasticsearch |

Ordre recommandé : réduire à la source, filtrer, batcher, bufferiser, ralentir
ou rejeter, puis augmenter la capacité après mesure.

## 2. Parcours par architecture

| Signal | v1 — Elastic classique | v2 — OpenTelemetry + Kafka | v3 — Hybride Fleet |
| --- | --- | --- | --- |
| Traces applicatives | Agent Elastic APM → APM Server → Logstash `5044` → Elasticsearch | Agent OTel → EDOT Gateway → Kafka `otel-traces` → EDOT backend → Elasticsearch | Même chemin que v2 |
| Logs applicatifs/Kubernetes | stdout → Elastic Agent Kubernetes → Logstash `5045` → Elasticsearch | stdout → EDOT DaemonSet → Kafka `otel-logs` → EDOT backend → Elasticsearch | Même chemin que v2 |
| Métriques applicatives | Agent/collecte Elastic → Logstash → Elasticsearch | Agent OTel → EDOT Gateway → Kafka `otel-metrics` → EDOT backend → Elasticsearch | `/actuator/prometheus` → EDOT Gateway Prometheus → Kafka `otel-metrics` → EDOT backend → Elasticsearch |
| Métriques Kubernetes | Elastic Agent/kube-state-metrics → Logstash → Elasticsearch | EDOT DaemonSet → Kafka `otel-metrics` → EDOT backend → Elasticsearch | Même chemin que v2 |
| Logs VM | Filebeat → Logstash → Elasticsearch | EDOT Agent VM → Kafka `otel-logs` → EDOT backend → Elasticsearch | Elastic Agent Fleet → Elasticsearch |
| Métriques VM | Metricbeat → Logstash → Elasticsearch | EDOT Agent VM → Kafka `otel-metrics` → EDOT backend → Elasticsearch | Elastic Agent Fleet → Elasticsearch |

Kafka est un buffer de télémétrie en v2 et pour les flux applicatifs/Kubernetes
de v3. En v1 il est uniquement une source observée ; les VM v3 ne publient pas
leur télémétrie dans Kafka.

## 3. Fiches des briques

Chaque fiche suit les quatre mêmes rubriques. Les liens pointent vers la
configuration IaC de référence.

### 3.1 Applications Java

**Rôle.** Produire les logs ECS, les traces et les métriques Actuator/Micrometer.

**Entrées.** Requêtes HTTP, tâches planifiées, Kafka et bases de données.

**Sorties.** Logs JSON sur stdout, endpoint `/actuator/prometheus` et signaux
transmis par l'agent Java actif.

**Pression.** Régler le niveau de logs, le sampling et la fréquence des
métriques à la source. Éviter `DEBUG` permanent et les labels à forte
cardinalité. Conserver les champs de corrélation.

Source : [`deployment.yaml`](../kubernetes/apps/supermarket-demo/base/deployment.yaml)
et [`application.yml`](../apps/supermarket-demo/order-service/src/main/resources/application.yml).

### 3.2 Agents Java Elastic APM et OpenTelemetry

**Rôle.** Instrumenter les applications et propager le contexte W3C.

**Entrées.** Transactions HTTP, appels sortants, Kafka, bases, métriques et
`traceparent`.

**Sorties.** v1 : APM vers APM Server. v2 : traces et métriques OTLP vers le
Gateway (`4317` gRPC ou `4318` HTTP). v3 : traces OTLP vers le Gateway ; les
métriques sont exposées par Actuator et scrappées par le Gateway. L'export de
logs par l'agent est désactivé en v2/v3 ; les logs restent sur stdout.

**Pression.** Utiliser le sampling pour les traces, le filtrage pour les
métriques cardinales et le niveau de logs pour les logs. Aucun sampling
explicite n'est versionné actuellement ; tout seuil doit préciser son unité et
sa perte acceptable.

Sources : variables `ELASTIC_APM_*` v1 et
[`otel-instrumentation.yaml`](../kubernetes/apps/supermarket-demo/v3/otel-instrumentation.yaml) v2/v3.

### 3.3 APM Server — v1

**Rôle.** Recevoir les événements APM et les remettre à Logstash.

**Entrées.** Requêtes APM HTTPS des agents Java.

**Sorties.** Lumberjack vers `apm-logstash:5044`.

**Pression.** Surveiller rejets, latence et erreurs de sortie. Réduire le
sampling côté agent avant d'augmenter l'aval. Aucune queue persistante APM
spécifique n'est déclarée.

Source : [`apm-server.yaml`](../v1/platform/kubernetes/base/observability/apm-server.yaml).

### 3.4 Agents de collecte Kubernetes

**Rôle.** Collecter les logs stdout et les métriques Kubernetes.

**Entrées.** v1 : `/var/log/containers`, `/var/log/pods`, kubelet et
kube-state-metrics. v2/v3 : `filelog/kubernetes` sur
`/var/log/pods/*/*/*.log` et `hostmetrics`.

**Sorties.** v1 : Beats vers Logstash `5045`. v2/v3 : Kafka `otel-logs` et
`otel-metrics` en OTLP protobuf. `k8sattributes` ajoute namespace, pod et
conteneur en v2/v3.

**Pression.** Filtrer probes et logs répétitifs, augmenter les périodes de
collecte et surveiller les événements abandonnés. Le DaemonSet EDOT applique un
batch de 512 éléments avec un délai de 1 s, mais ne possède pas le
`memory_limiter` du Gateway.

Sources : [`kubernetes-logs-agent.yaml`](../v1/platform/kubernetes/base/observability/kubernetes-logs-agent.yaml)
et [`otel-kafka.yaml`](../v3/platform/kubernetes/base/observability/otel-kafka.yaml).

### 3.5 Filebeat et Metricbeat — v1

**Rôle.** Collecter la télémétrie des VM de l'architecture classique.

**Entrées.** Logs système et services, métriques système et intégrations
Kafka/MongoDB/PostgreSQL selon la policy.

**Sorties.** Beats vers Logstash, puis data streams Elasticsearch.

**Pression.** Réduire les chemins surveillés et les périodes avant d'augmenter
les queues. Surveiller erreurs de sortie, rotations manquées et remplissage des
queues.

### 3.6 EDOT Agent VM — v2

**Rôle.** Collecter les logs et métriques VM dans le chemin OTLP/Kafka.

**Entrées.** `/var/log/messages`, `/var/log/secure`, logs Kafka, MongoDB et
PostgreSQL ; receivers `hostmetrics`, `kafka_metrics`, `mongodb` et
`postgresql`.

**Sorties.** Kafka `otel-logs` et `otel-metrics` en OTLP protobuf.

**Pression.** `memory_limiter` à 256 MiB avec pic de 64 MiB, batch de 256/1 s,
queue persistante et retry Kafka. Réduire fichiers et fréquences avant
d'augmenter la queue.

Source : [`otel-agent.yml.j2`](../v2/ansible/templates/otel-agent.yml.j2).

### 3.7 Elastic Agent Fleet VM — v3

**Rôle.** Collecter et expédier directement la télémétrie des VM.

**Entrées.** Journald, métriques système, Kafka/Jolokia, MongoDB et PostgreSQL.

**Sorties.** Sortie Fleet vers Elasticsearch, dans `logs-*` et `metrics-*`.

**Pression.** Réduire les périodes, désactiver les inputs inutiles et filtrer
les événements répétitifs. Aucun quota global par VM n'est configuré ; un
plafond strict doit être appliqué en amont et surveillé.

Source : policy `data-fleet` dans [`kibana.yaml`](../v3/platform/kubernetes/base/observability/kibana.yaml).

### 3.8 EDOT Gateway — v2/v3

**Rôle.** Recevoir les signaux OTLP applicatifs, traiter les traces APM et
publier dans Kafka.

**Entrées.** v2 : OTLP gRPC `4317` et HTTP `4318` depuis les applications Java.
v3 : OTLP pour les traces et receiver Prometheus pour les endpoints
`/actuator/prometheus` des trois Services applicatifs, toutes les 15 secondes.

**Sorties.** `otel-traces`, `otel-metrics` et `otel-logs` en OTLP protobuf.
Le connector `elasticapm` produit les métriques APM agrégées à partir des traces.
Les métriques Prometheus scrappées sont envoyées sur `otel-metrics`.

**Pression.** `memory_limiter` à 400 MiB avec pic de 100 MiB, puis batch de 512/1
s. Le scrape v3 est limité par `scrape_interval: 15s` ; réduire la fréquence ou
filtrer les métriques avant d'augmenter les ressources. Réduire ou filtrer en
amont si la mémoire est sous pression ; ne pas retirer le limiteur.

Source : [`otel-kafka.yaml`](../v3/platform/kubernetes/base/observability/otel-kafka.yaml).

### 3.9 Kafka — v2/v3 applicatif/Kubernetes

**Rôle.** Bufferiser entre producteurs et Collector backend.

**Entrées.** OTLP protobuf du Gateway, du DaemonSet et de l'Agent VM v2.

**Sorties.** Groupe consommateur `otel-backend` sur `otel-traces`, `otel-logs`
et `otel-metrics`.

**Pression.** Surveiller consumer lag, débit des producteurs et espace disque.
Un lag croissant impose de réduire sampling/filtrage ou d'augmenter les
consommateurs. Le facteur de réplication vaut 1 dans ce POC.

Sources : [`observability-kafka.container.j2`](../v3/ansible/templates/observability-kafka.container.j2)
et [`site.yml`](../v3/ansible/site.yml).

### 3.10 EDOT backend collector — v2/v3

**Rôle.** Consommer Kafka, enrichir, mapper ECS et indexer Elasticsearch.

**Entrées.** Les trois topics Kafka via le groupe `otel-backend`.

**Sorties.** Elasticsearch interne ; les traces produisent les métriques APM
agrégées et les logs conservent `trace.id`/`span.id`.

**Pression.** `memory_limiter` à 700 MiB avec pic de 150 MiB, batch de 512/1 s et
queue disque persistante de 1 000 éléments. Surveiller retries, queue, lag et
rejets d'indexation ; réduire le débit avant que la queue soit pleine.

Source : [`otel-kafka.yaml`](../v3/platform/kubernetes/base/observability/otel-kafka.yaml).

### 3.11 Logstash — v1

**Rôle.** Recevoir, enrichir, router et envoyer les signaux classiques.

**Entrées.** APM Server/Lumberjack `5044` et Elastic Agent/Beats `5045`.

**Sorties.** Elasticsearch avec routage automatique des data streams et ECS v8.

**Pression.** Séparer les pipelines APM/Kubernetes, filtrer avant indexation,
surveiller workers, latence et queue persistante. La queue absorbe une panne
courte mais ne constitue pas un rate limiter.

Source : [`apm-logstash.yaml`](../v1/platform/kubernetes/base/observability/apm-logstash.yaml).

### 3.12 Elasticsearch, Kibana et Fleet

**Rôle.** Elasticsearch indexe et stocke les trois signaux. Kibana fournit les
recherches, data views et dashboards. Fleet Server distribue les policies aux
agents v3 ; ECK orchestre les ressources Elastic.

**Entrées.** Documents ECS depuis Logstash, EDOT backend ou Fleet ; état des
agents et policies.

**Sorties.** Data streams `logs-*`, `metrics-*`, traces APM et dashboards.

**Pression.** Surveiller rejets d'indexation, latence, CPU, mémoire et disque.
Ces composants ne sont pas un buffer : la réduction de débit se fait en amont.

## 4. Règles de pression par signal

### Logs

Régler le niveau applicatif, exclure probes et répétitions, parser/enrichir une
seule fois, limiter les fichiers suivis et alerter sur les pertes. Préserver
`trace.id`, `span.id`, `service.name` et le namespace.

### Traces

Conserver les erreurs et transactions lentes, appliquer le sampling avant
d'augmenter les queues, puis suivre erreurs APM/OTLP, lag Kafka et rejets
Elasticsearch. Vérifier que les métriques APM agrégées restent disponibles.

### Métriques

Augmenter l'intervalle avant les ressources, réduire labels et familles
inutiles, et surveiller les séries actives. Conserver les métriques nécessaires
aux dashboards et à la santé de la chaîne.

## 5. État actuel et limites

| Architecture | Protections actives | Limites |
| --- | --- | --- |
| v1 | Sampling disponible côté agent, filtrage/routage Logstash, queues selon les agents | Aucun rate limit numérique commun versionné |
| v2 | `memory_limiter`, batch, queue/retry VM, queue backend, Kafka | Aucun quota par service/namespace ; aucun sampling explicite versionné |
| v3 | Protections v2 pour applications/Kubernetes ; périodes et filtrage Fleet pour VM | Aucun quota Fleet global ; les VM n'ont pas de buffer Kafka |

Le POC ne définit pas de plafond strict commun en événements/s, spans/s,
octets/s ou séries actives. Avant d'en ajouter un, mesurer le débit, choisir
l'unité, définir l'action de dépassement et l'alerte, puis tester la reprise.

## 6. Vérification opératoire

Après modification d'un manifest ou d'une policy :

```bash
make kubernetes-validate
make vm-status
kubectl -n elastic-stack get deployment otel-gateway otel-kafka-exporter
kubectl -n elastic-stack logs deployment/otel-kafka-exporter --tail=50
```

Le résultat attendu est : composants prêts, aucune erreur persistante de
collecte ou d'indexation, consumer lag stable, queues non saturées et data
streams alimentés. Toute réduction de débit doit avoir une mesure avant/après
et une procédure de retour à la normale.
