# Inventaire des métriques et dashboards ELK

Cette référence s'adresse aux opérateurs qui doivent qualifier les intégrations
Kafka, MongoDB, PostgreSQL et System dans ELK. Elle indique les métriques
attendues d'après les policies versionnées, les dashboards disponibles dans
Kibana et la requête Elasticsearch qui vérifie leur présence.

Elle ne remplace pas la [matrice des métriques et de leurs sources](metriques-sources.md),
qui décrit aussi les profils EDOT et Beats. L'inventaire ci-dessous porte sur
les data streams utilisés par les dashboards d'intégration et sur le contrôle
de leur indexation.

## Périmètre de la vérification

La vérification a été exécutée le **21 août 2026 à 07:39 UTC**, sur
Elasticsearch `9.5.0` et Kibana `9.5.1`. Les 26 data streams métriques attendus
étaient présents avec un document récent : 10 pour Kafka, 5 pour MongoDB, 3
pour PostgreSQL et 8 pour System.

Les documents historiques supplémentaires ne constituent pas une preuve de la
configuration actuelle. Par exemple, des streams `kafka.consumer` ou
`system.*.otel` plus anciens peuvent rester indexés sans être requis par les
policies Fleet décrites ici.

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

Les collectes Kafka sont configurées toutes les 60 secondes sur le profil
Elastic Agent. Les streams `broker`, `partition` et `consumergroup` viennent du
protocole Kafka ; les autres viennent des MBeans JMX exposés par Jolokia.

| Data stream attendu | Métriques ou état attendu | Dashboards principaux | Présence Elasticsearch |
| --- | --- | --- | --- |
| `kafka.broker` | identité et activité du broker | Overview | présente, hôtes `data-01` à `data-03` |
| `kafka.partition` | partitions, leader et réplication | Overview | présente, hôtes `data-01` à `data-03` |
| `kafka.consumergroup` | groupes consommateurs et lag | Overview | présente, hôtes `data-01` à `data-03` |
| `kafka.controller` | contrôleur et état KRaft | Controller | présente, hôtes `data-01` à `data-03` |
| `kafka.jvm` | heap, GC et threads JVM | JVM | présente, hôtes `data-01` à `data-03` |
| `kafka.network` | requêtes et trafic réseau | Network | présente, hôtes `data-01` à `data-03` |
| `kafka.log_manager` | segments et journaux Kafka | Log manager | présente, hôtes `data-01` à `data-03` |
| `kafka.replica_manager` | réplication et ISR | Replica manager | présente, hôtes `data-01` à `data-03` |
| `kafka.topic` | débit, partitions et réplication par topic | Topic | présente, hôtes `data-01` à `data-03` |
| `kafka.raft` | voters, leader et quorum KRaft | Raft | présente, hôtes `data-01` à `data-03` |

## MongoDB

Les streams MongoDB sont collectés toutes les 60 secondes. Le dashboard
SystemLens s'appuie spécifiquement sur `mongodb.replstatus` pour afficher le
replica set et son primary courant.

| Data stream attendu | Métriques ou état attendu | Dashboards principaux | Présence Elasticsearch |
| --- | --- | --- | --- |
| `mongodb.collstats` | opérations et temps par collection | Metrics Overview | présente |
| `mongodb.dbstats` | taille, stockage et objets par base | Metrics Overview | présente |
| `mongodb.metrics` | connexions, mémoire et activité serveur | Metrics Overview | présente |
| `mongodb.replstatus` | primary/secondary, lag et oplog | SystemLens · MongoDB clusters | présente |
| `mongodb.status` | état global `serverStatus` | Metrics Overview | présente |

Les documents actuels sont observés sur `data-01`, `data-02` et `data-03`.
Des identités historiques (`mongodb-01`, `localhost`) existent aussi dans
l'index et ne doivent pas être utilisées pour qualifier le profil actuel.

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
| `system.cpu` | utilisation CPU | Metrics System · Overview / Host overview | présente |
| `system.memory` | mémoire utilisée et disponible | Metrics System · Overview / Host overview | présente |
| `system.load` | charge système | Metrics System · Overview | présente |
| `system.network` | paquets et octets réseau | Metrics System · Overview | présente |
| `system.process.summary` | nombre de processus par état | Metrics System · Overview | présente |
| `system.uptime` | disponibilité de l'hôte | Metrics System · Host overview | présente |
| `system.filesystem` | utilisation par point de montage | Metrics System · Host overview | présente |
| `system.fsstat` | capacité agrégée des systèmes de fichiers | Metrics System · Host overview | présente |

Les hôtes courants de ce profil sont `data-01`, `data-02` et `data-03`.
`localhost` et les data streams suffixés `.otel` sont des données d'autres
profils ou historiques : les examiner séparément plutôt que de les additionner
au même graphique.

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
          "size": 100,
          "include": "(kafka\\.(broker|partition|consumergroup|controller|jvm|network|log_manager|replica_manager|topic|raft)|mongodb\\.(collstats|dbstats|metrics|replstatus|status)|postgresql\\.(activity|bgwriter|database)|system\\.(cpu|memory|load|network|process\\.summary|uptime|filesystem|fsstat))"
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

La sortie doit contenir les 26 noms de data streams listés dans cet inventaire.
Un stream absent ou dont `dernier_document` est plus ancien que deux intervalles
de collecte doit être diagnostiqué avant de conclure que le dashboard est en
cause. Utiliser alors le guide
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
