# Inventaire des métriques et dashboards ELK

Cette référence s'adresse aux opérateurs qui doivent qualifier les métriques
Kafka, MongoDB, PostgreSQL et System dans Elasticsearch et Kibana. Elle relie,
pour chaque profil de collecte, la source, la fréquence, le périmètre de
l'hôte et le contrôle à effectuer dans Elasticsearch.

Les noms de data stream décrivent précisément les packages Elastic Agent. Pour
EDOT, le nom effectivement produit par l'exporteur doit être relevé dans
Discover : les receivers OpenTelemetry n'ont pas nécessairement le même
`data_stream.dataset` qu'une intégration Elastic. La [matrice des métriques et
de leurs sources](metriques-sources.md) reste la référence transversale.

## Profils couverts

| Profil | Hôte | Métriques couvertes | Fréquence |
| --- | --- | --- | --- |
| EDOT | `data-01` | System, MongoDB, Kafka, PostgreSQL | 30 s pour System ; 60 s pour les services |
| Elastic Agent piloté par Fleet | `data-02` | System, MongoDB, Kafka et JMX Kafka | 30 s ou 60 s selon le stream |
| Filebeat + Metricbeat | `data-03` | System, MongoDB, Kafka (broker, partitions, consumer groups) | 30 s ou 60 s selon le stream |

Ces profils sont exclusifs : ne pas additionner leurs séries pour comparer des
hôtes, ni conclure qu'une métrique JMX est absente parce qu'elle n'est pas
collectée par EDOT ou Metricbeat.

## Périmètre de la vérification

La dernière vérification consignée a été exécutée le **21 août 2026 à 07:39
UTC**, avec Elasticsearch et Kibana `8.5.1`. Elle doit être rejouée après toute
modification de policy, de receiver EDOT ou de mapping d'exporteur.

Les documents historiques ne constituent pas une preuve de la configuration
actuelle. En particulier, un document `kafka.*` ou `system.*.otel` associé à un
autre hôte ne valide pas la policy Fleet de `data-02`.

## Dashboards disponibles dans Kibana

| Domaine | Dashboards observés | Usage |
| --- | --- | --- |
| Kafka | `[Metrics Kafka] Overview`, `Controller`, `JVM`, `Network`, `Log manager`, `Replica manager`, `Consumer`, `Producer`, `Raft`, `Topic` ; `[Logs Kafka] Overview` | santé du broker, KRaft, JVM, trafic, réplication, topics et logs |
| MongoDB | `[Metrics MongoDB] Overview`, `[Logs MongoDB] Overview`, `SystemLens · MongoDB clusters` | état serveur, journaux et rôle primary du replica set |
| PostgreSQL | `[Metrics PostgreSQL] Database Overview`, `[Logs PostgreSQL] Overview`, `[Logs PostgreSQL] Query Duration Overview` | activité et taille de base, journaux et durée de requêtes |
| System | `[Metrics System] Overview`, `[Metrics System] Host overview`, dashboards `[OTel] Hosts Overview` et `Host Details` ; dashboards de logs System | ressources hôte, inventaire et journaux système |

Les dashboards Kafka, PostgreSQL et System sont des assets d'intégration Kibana.
Le dashboard `SystemLens · MongoDB clusters` est l'asset personnalisé versionné
dans ce dépôt.

## Kafka

Les dix datasets ci-dessous sont ceux du profil Elastic Agent/Fleet sur
`data-02`, collectés toutes les 60 secondes. Les streams `broker`, `partition`
et `consumergroup` viennent du protocole Kafka ; les autres viennent des
MBeans JMX exposés par Jolokia. EDOT et Metricbeat couvrent un sous-ensemble :
voir les sections dédiées plus bas.

| Data stream attendu | Métriques ou état attendu | Dashboards principaux | Présence Elasticsearch |
| --- | --- | --- | --- |
| `kafka.broker` | identité et activité du broker | Overview | attendu sur `data-02` |
| `kafka.partition` | partitions, leader et réplication | Overview | attendu sur `data-02` |
| `kafka.consumergroup` | groupes consommateurs et lag | Overview | attendu sur `data-02` |
| `kafka.controller` | contrôleur et état KRaft | Controller | attendu sur `data-02` |
| `kafka.jvm` | heap, GC et threads JVM | JVM | attendu sur `data-02` |
| `kafka.network` | requêtes et trafic réseau | Network | attendu sur `data-02` |
| `kafka.log_manager` | segments et journaux Kafka | Log manager | attendu sur `data-02` |
| `kafka.replica_manager` | réplication et ISR | Replica manager | attendu sur `data-02` |
| `kafka.topic` | débit, partitions et réplication par topic | Topic | attendu sur `data-02` |
| `kafka.raft` | voters, leader et quorum KRaft | Raft | attendu sur `data-02` |

## MongoDB

Les streams MongoDB ci-dessous sont collectés toutes les 60 secondes par le
profil Fleet sur `data-02`. Le dashboard SystemLens s'appuie spécifiquement
sur `mongodb.replstatus` pour afficher le replica set et son primary courant.

| Data stream attendu | Métriques ou état attendu | Dashboards principaux | Présence Elasticsearch |
| --- | --- | --- | --- |
| `mongodb.collstats` | opérations et temps par collection | Metrics Overview | attendu sur `data-02` |
| `mongodb.dbstats` | taille, stockage et objets par base | Metrics Overview | attendu sur `data-02` |
| `mongodb.metrics` | connexions, mémoire et activité serveur | Metrics Overview | attendu sur `data-02` |
| `mongodb.replstatus` | primary/secondary, lag et oplog | SystemLens · MongoDB clusters | attendu sur `data-02` |
| `mongodb.status` | état global `serverStatus` | Metrics Overview | attendu sur `data-02` |

Les mêmes familles sont aussi collectées par EDOT sur `data-01` et Metricbeat
sur `data-03`, mais il faut les contrôler selon leur convention de données
propre. Ne pas utiliser `localhost` ou une ancienne identité d'hôte comme
preuve de la policy Fleet actuelle.

## PostgreSQL

PostgreSQL est collecté par EDOT sur la VM OpenTelemetry. Le pipeline actif
indexe les trois streams ci-dessous. L'asset Kibana référence aussi les
statistiques de requêtes `postgresql.statement.*` ; elles sont distinguées dans
la dernière ligne, car elles ne sont pas mappées ni indexées au moment de la
vérification.

| Data stream attendu | Métriques ou état attendu | Dashboards principaux | Présence Elasticsearch |
| --- | --- | --- | --- |
| `postgresql.activity` | sessions, activité et requêtes en cours | Metrics PostgreSQL · Database Overview | présente sur `data-01` |
| `postgresql.bgwriter` | checkpoints et buffers écrits | Metrics PostgreSQL · Database Overview | présente sur `data-01` |
| `postgresql.database` | taille, connexions et transactions par base | Metrics PostgreSQL · Database Overview | présente sur `data-01` |
| `postgresql.statement` | texte, appels, lecture cache et temps total de requête, dont `postgresql.statement.query.time.total.ms` | Metrics PostgreSQL · Database Overview : Query Latency et Top Queries | attendue par le dashboard, **absente** du pipeline actif |

Le panneau **Query Latency** calcule notamment la différence de
`max(postgresql.statement.query.time.total.ms)`. Une recherche Elasticsearch
sur ce champ, ainsi qu'une lecture de ses mappings, ne retournent aucun
document ni champ à la date de vérification. Le panneau peut donc rester vide
même lorsque les trois autres streams PostgreSQL sont présents.

Pour rendre ces visualisations exploitables, qualifier séparément la collecte
des statistiques de requêtes : configuration du receiver PostgreSQL, exposition
des statistiques par la base et conséquences de cardinalité liées au texte des
requêtes. Ne pas déclarer le stream comme présent avant d'avoir vérifié des
documents indexés.

## System

Les données System du profil Elastic Agent sont collectées toutes les 30 secondes
pour CPU, mémoire, charge, réseau, processus et uptime, et toutes les minutes
pour les systèmes de fichiers. Les vues OTel complètent ces dashboards pour les
hôtes observés par EDOT.

| Data stream attendu | Métriques ou état attendu | Dashboards principaux | Présence Elasticsearch |
| --- | --- | --- | --- |
| `system.cpu` | utilisation CPU | Metrics System · Overview / Host overview | attendu sur `data-02` |
| `system.memory` | mémoire utilisée et disponible | Metrics System · Overview / Host overview | attendu sur `data-02` |
| `system.load` | charge système | Metrics System · Overview | attendu sur `data-02` |
| `system.network` | paquets et octets réseau | Metrics System · Overview | attendu sur `data-02` |
| `system.process.summary` | nombre de processus par état | Metrics System · Overview | attendu sur `data-02` |
| `system.uptime` | disponibilité de l'hôte | Metrics System · Host overview | attendu sur `data-02` |
| `system.filesystem` | utilisation par point de montage | Metrics System · Host overview | attendu sur `data-02` |
| `system.fsstat` | capacité agrégée des systèmes de fichiers | Metrics System · Host overview | attendu sur `data-02` |

Les hôtes `data-01` et `data-03` publient également des métriques système,
respectivement avec EDOT et Metricbeat ; elles ne valident pas les huit
datasets Fleet ci-dessus.

## EDOT sur `data-01`

EDOT collecte directement sur `data-01`. Les métriques sont exportées au format
OpenTelemetry/ECS ; relever leur dataset exact dans Discover avant de les
utiliser dans un dashboard conçu pour une intégration Elastic.

| Source | Métriques attendues | Fréquence | Limite connue |
| --- | --- | --- | --- |
| `host_metrics` | CPU, compte de CPU logiques, charge, mémoire, réseau, systèmes de fichiers | 30 s | `host.name` est recopié par le pipeline de compatibilité ; vérifier les autres champs avant réutilisation d'un dashboard System |
| receiver MongoDB | opérations, connexions, stockage et replica set local | 60 s | le nom de dataset peut différer de `mongodb.*` |
| receiver Kafka | brokers, topics et consommateurs | 60 s | pas de JVM, KRaft, réseau ou réplication JMX dans cette configuration |
| receiver PostgreSQL | activité, bgwriter et bases | 60 s | `postgresql.statement` n'est pas alimenté |

## Metricbeat sur `data-03`

Metricbeat collecte localement sur `data-03`. Les datasets System, MongoDB et
Kafka sont ceux des modules Metricbeat ; les trois familles Kafka actives sont
`broker`, `partition` et `consumergroup`. Les métriques JMX Kafka ne font pas
partie de ce profil. Contrôler que `host.name : "data-03"` est présent avant de
comparer cette collecte à celle de Fleet.

## Requête Elasticsearch reproductible

Cette requête agrège les documents de `metrics-*` par `data_stream.dataset`,
retourne leur nombre, leur dernier horodatage et les hôtes associés. Elle est en
lecture seule. Exécuter depuis la racine du dépôt avec un accès Kubernetes
autorisé ; le mot de passe ne s'affiche pas.

```bash
es_password="$(kubectl -n elastic-stack get secret elasticsearch-es-elastic-user \
  -o jsonpath='{.data.elastic}' | base64 --decode)"

curl --fail --silent --show-error --insecure \
  --resolve elasticsearch.poc.test:443:127.0.0.1 \
  -u "elastic:${es_password}" \
  -H 'Content-Type: application/json' \
  -X POST 'https://elasticsearch.poc.test:443/metrics-*/_search' \
  --data '{
    "size": 0,
    "aggs": {
      "datasets": {
        "terms": {
          "field": "data_stream.dataset",
          "size": 200
        },
        "aggs": {
          "documents": {"value_count": {"field": "_index"}},
          "dernier_document": {"max": {"field": "@timestamp"}},
          "hosts": {
            "terms": {
              "field": "host.name",
              "size": 10,
              "missing": "(sans host.name)"
            }
          }
        }
      }
    }
  }' | jq '{
    total: .hits.total.value,
    datasets: [.aggregations.datasets.buckets[] | {
      dataset: .key,
      documents: .documents.value,
      dernier_document: .dernier_document.value_as_string,
      hosts: [.hosts.buckets[].key]
    }]
  }'
```

Lire la liste `hosts` retournée pour chaque dataset avant de conclure. Sur
`data-02`, les 23 datasets Fleet (10 Kafka, 5 MongoDB et 8 System) doivent être
présents et récents. Sur `data-01`, relever les datasets EDOT réellement
produits pour les quatre receivers. Sur `data-03`, contrôler les huit datasets
System, les cinq MongoDB et les trois Kafka configurés par Metricbeat.

Un dataset absent ou dont `dernier_document` est plus ancien que deux
intervalles de collecte doit être diagnostiqué avant de conclure que le
dashboard est en cause. Utiliser alors le guide
[Diagnostiquer un dashboard vide](how-to/diagnostiquer-dashboard-vide.md).

Pour contrôler spécifiquement la métrique attendue par le panneau Query
Latency, remplacer l'agrégation par la requête suivante :

```json
{
  "query": {
    "exists": {
      "field": "postgresql.statement.query.time.total.ms"
    }
  }
}
```

Un total égal à `0` confirme que le panneau est une attente de dashboard non
alimentée, et non une panne des streams `activity`, `bgwriter` ou `database`.
