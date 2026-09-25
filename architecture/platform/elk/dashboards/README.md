# Dashboards Kibana

Les fichiers `.ndjson` sont des exports d'objets sauvegardés Kibana. Le fichier
`business-metrics-dashboard.json` est une définition inline de l'API Dashboard
Kibana, avec des visualisations ES|QL. La collecte des VM est assurée par Elastic Agent EDOT standalone et envoyée à
Elasticsearch. Les packages Fleet sont installés par la cible
`make fleet-assets-deploy`. L’installation fournit les dashboards natifs des
packages ; aucun script ne les réécrit ensuite. Les dashboards Fleet classiques
restent des assets de compatibilité ; les contrôles
ci-dessous ciblent les data streams OTel réellement produits par le chemin
EDOT standalone → Edge → Kafka → backend.

## Dashboards à utiliser

| Besoin | Dashboard Kibana | Jeux de données attendus | Indicateurs à suivre |
| --- | --- | --- | --- |
| Santé des hôtes | Vue OTel System / Infrastructure Inventory / Discover | `metrics-hostmetricsreceiver.otel-*` | CPU (`system.cpu.utilization`), mémoire (`system.memory.utilization`), disque et réseau. |
| Santé du cluster | **[Kubernetes OTel] Overview**, **Nodes**, **Workloads**, **Pods** | `kubeletstatsreceiver.otel`, `k8sclusterreceiver.otel` | CPU/mémoire par pod et nœud, état du cluster, déploiements, conteneurs, volumes et capacité observée par `kubeletstats`/`k8s_cluster`. |
| Brokers et consommateurs | Vue OTel Kafka / Discover | `metrics-kafkametricsreceiver.otel-*` | Brokers, partitions, réplication, lag et consumer groups. |
| Logs Kafka | Discover | `logs-generic-*` | Logs Kafka collectés par `filelog/system`, avec hôte et chemin source. |
| MongoDB | Vue OTel MongoDB / Discover | `metrics-mongodbreceiver.otel-*` | Connexions, opérations, mémoire, cache et stockage ; les indicateurs de réplication nécessitent un replica set, alors que le POC utilise un MongoDB standalone. |
| Logs MongoDB | Discover | `logs-generic-*` | Logs `mongod`, erreurs, démarrage et événements du serveur. |
| Base PostgreSQL | Vues OTel PostgreSQL / Discover | `metrics-postgresqlreceiver.otel-*` | Sessions, transactions, taille des bases et activité du bgwriter. |
| Logs PostgreSQL | Discover | `logs-generic-*` | Logs PostgreSQL et événements du serveur ; les statistiques de requêtes nécessitent une collecte dédiée. |
| Services applicatifs | Observability > APM > Services et Discover | `apm.service_transaction.1m`, `apm.transaction.1m`, `apm.app.*`, `metrics-generic.otel-*`, traces APM/OTLP | Débit, latence p50/p95/p99, taux d'erreur, dépendances, traces et métriques Actuator scrappées. |
| Métriques métier | **Métriques métier — Supermarket Demo** | `metrics-generic.otel-*` | `metrics.business.orders.completed`, `metrics.business.stock.restock.requested`, `metrics.business.stock.restock.completed` et `metrics.business.stock.quantity`, avec ventilation des commandes par `attributes.channel`. |
| SLA pains achetés | **Observability > SLOs** et **Alerts and Insights > Rules** | `logs-*` | SLO à 99 % de périodes de 24 heures conformes sur 30 jours, avec au moins 10 pains `BREAD-WHOLE` achetés par période ; alerte sur les dernières 24 heures. |
| Santé de la collecte | État EDOT, logs et consumer lag Kafka | journaux systemd, `logs-generic-*` et `metrics-kafkametricsreceiver.otel-*` | Agents EDOT healthy, absence d'erreurs d'export et débit des topics applicatifs/Kubernetes. |
| Fiabilité des Collectors | **Alerts** et, avec une licence Platinum, SLO Kibana | `metrics-generic.otel-*` | Échecs d'export, queue backend proche de la saturation et scrape Actuator indisponible. |

Les métriques Prometheus des applications sont scrappées par jobs distincts (`order-service`, `inventory-service` et `restock-service`) afin que les courbes techniques et les tableaux puissent conserver une série par microservice.

Les métriques OTel Kubernetes sont consultables dans les dashboards **[Kubernetes OTel]**
installés par le package `kubernetes_otel`. Les dashboards classiques **[Metrics Kubernetes]**
attendent le schéma de l’Elastic Agent Kubernetes autonome et ne sont pas alimentés par
le flux `kubeletstats` de cette architecture.

Le package Fleet `kubernetes_otel` installe onze dashboards Kubernetes OTel avec des requêtes ES|QL
embarquées. Le plan conserve ces dashboards natifs sans réécriture automatique.
La cible `make kubernetes-otel-dashboards-verify` contrôle leurs références de
data streams et de champs lorsque les données sont présentes.

Les métriques doivent être filtrées par environnement (`deployment.environment.name`),
service (`service.name`) et hôte (`host.name`) avant d'interpréter une alerte.
Pour ce POC, PostgreSQL est attendu uniquement sur `poc-01`; le dashboard ne
doit afficher les métriques PostgreSQL de `poc-01`.

Le panneau `Connection Utilization Gauge` des vues PostgreSQL affiche un
pourcentage calculé par `postgresql.backends / postgresql.connection.max`, borné
entre 0 et 1. `postgresql.db_size` reste une taille absolue et ne doit pas être
présentée comme un pourcentage sans métrique de capacité de référence.

## Déploiement et vérification

Déployer la configuration déclarative des intégrations Fleet :

```bash
make kubernetes-validate
make fleet-assets-deploy
make business-dashboard-deploy
make observability-policies-deploy
```

Vérifier ensuite que les sources de tous les dashboards ont publié des
documents sur les quinze dernières minutes :

```bash
make dashboards-verify
make postgresql-otel-dashboards-verify
```

La cible n'affiche aucun secret et vérifie les data streams attendus ainsi que
les métriques clés ci-dessus. Les audits détaillés des dashboards de package
restent explicites avec `make postgresql-otel-dashboards-verify` et
`make kubernetes-otel-dashboards-verify`. Ils peuvent signaler des panneaux
optionnels incompatibles avec les métriques réellement exposées ; ils ne
réécrivent pas les dashboards et ne sont pas inclus dans le contrôle de santé
des data streams.

Les dashboards OTel System, Kafka, MongoDB et tous les dashboards PostgreSQL OTel partagent un filtre
`Hôte` basé sur `resource.attributes.host.name`. Les anciens filtres propres
aux intégrations classiques (`attributes.mongodb.instance` ou un nom de base
non présent dans les documents OTel) ne doivent pas être réintroduits : ils
produisent un sélecteur vide ou en erreur.

Le receiver PostgreSQL OTel de ce POC expose les sessions, transactions, taille
des bases, compteurs du bgwriter, verrous, deadlocks et compteurs de tuples. Les
événements `db.server.query_sample` et `db.server.top_query` sont activés grâce
à `pg_stat_activity` et `pg_stat_statements`. Leur disponibilité dépend des
droits de l’utilisateur `otel` créés par Ansible.

Le dashboard métier versionné est importé explicitement par
`make business-dashboard-deploy`. Il n’est pas importé automatiquement par
`make elk-deploy`. Le script
`platform/elk/scripts/replace-kibana-dashboard.sh` délègue à l'API `PUT` de Kibana :
l'ancien objet reste disponible si la nouvelle définition est refusée ;
`make business-dashboard-replace` fournit un alias explicite. Il apparaît dans Kibana sous
**Métriques métier — Supermarket Demo**. Les panneaux utilisent le maximum du
compteur cumulatif dans chaque intervalle ; le filtre temporel Kibana doit donc
être positionné sur une période où les métriques sont présentes.

Le dashboard contient quatre indicateurs synthétiques et trois graphiques ES|QL
inline : commandes finalisées, réassorts demandés, réassorts terminés, écart de
réassort, évolution des commandes et des réassorts, puis ventilation des
commandes par canal (`REST` et `Kafka`). Les valeurs sont les deltas des
compteurs sur chaque bucket ; elles représentent donc un volume de période et
non la valeur cumulée brute du compteur.

La vue inclut également quatre panneaux de santé applicative : requêtes HTTP
actives, tendances CPU et mémoire JVM, puis surcharge GC. Ces indicateurs
sont calculés sur la période sélectionnée et peuvent être vides si le flux de
métriques applicatives n'est pas alimenté.

L'ordre visuel regroupe les panneaux par parcours de lecture : indicateurs et
graphiques métier, stock, requêtes HTTP actives, traitements Kafka, puis
saturation CPU, mémoire et GC JVM. Les métriques de latence HTTP et d'appels
HTTP sortants ne sont pas exposées par la collecte OTel actuelle ; ces analyses
restent disponibles dans APM lorsque le flux de traces est alimenté.

Les filtres KQL doivent conserver une expression entre parenthèses. Une
expression générée avec un groupe vide (`and ()metrics...`) est invalide ; la
forme équivalente correcte est par exemple :
`data_stream.dataset:"generic.otel" and (metrics.business.orders.completed:* or metrics.business.stock.restock.requested:* or metrics.business.stock.restock.completed:*)`.
Le dashboard API ci-dessus n'embarque pas ce filtre global et évite ainsi la
réutilisation d'un filtre KQL vide provenant d'un ancien export.

Le panneau **Commandes finalisées — REST / Kafka · cliquer sur une barre pour le
diagnostic** constitue le
premier niveau de drill-down métier : les séries sont calculées à partir de
`attributes.channel`, puis un clic sur une série ouvre le dashboard
**Diagnostic technique — commandes** en conservant le filtre REST ou Kafka et
la période sélectionnée. Ce dashboard cible affiche l'évolution temporelle
des commandes filtrées. Les vues techniques complémentaires sont APM
> Services/Transactions pour le chemin HTTP REST, et les dashboards Kafka pour
les producteurs, consommateurs et le lag du chemin Kafka.

Le drill-down se déclenche sur une barre du graphique en mode consultation.
Cliquer sur la légende ne fait qu'afficher ou masquer une série ; le menu
**Options du panneau > Créer un drilldown** permet de contrôler la configuration
en mode édition.

## SLO et alertes versionnés

[`../alerts/observability-policies.json`](../alerts/observability-policies.json)
est la source de vérité versionnée pour la disponibilité Actuator et les alertes
de collecte. `make observability-policies-deploy` crée ou met à jour :

- un SLO de disponibilité à 99,5 % par microservice sur 30 jours ;
- un SLO métier à 99 % de tranches quotidiennes conformes sur 30 jours, une
  tranche étant conforme à partir de 10 unités `BREAD-WHOLE` vendues ;
- une alerte sur les échecs d'export OTel ;
- une alerte sur une queue d'export OTel supérieure ou égale à 800 lots ;
- une alerte lorsqu'un scrape Actuator retourne `up=0` ;
- une alerte horaire lorsque les ventes de pain restent sous 10 unités sur les
  dernières 24 heures.

L'API SLO nécessite une licence Elastic compatible. Avec une licence Basic, la cible
signale que le SLO est ignoré et poursuit la réconciliation des alertes
compatibles.

Les règles créent des alertes dans Kibana mais n'envoient pas de notification
externe par défaut. Associer ensuite un connecteur versionné ou administré par
le coffre opérationnel, sans stocker de secret dans ce dépôt.

## Documentation externe

- [Importer et exporter des objets sauvegardés Kibana](https://www.elastic.co/docs/explore-analyze/visualize/kibana/management)
- [Créer des dashboards Kibana](https://www.elastic.co/docs/explore-analyze/dashboards)
