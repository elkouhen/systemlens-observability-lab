# Dashboards Kibana

Les fichiers `.ndjson` sont des exports d'objets sauvegardés Kibana. Le fichier
`business-metrics-dashboard.json` est une définition inline de l'API Dashboard
Kibana, avec des visualisations ES|QL. La collecte v3 des VM est assurée par Elastic Agent Fleet et envoyée directement à
Elasticsearch. Les packages Fleet sont installés par la configuration Quadlet
de `elk-01` puis réconciliés par le script de bootstrap Fleet.
Les dashboards Fleet classiques peuvent donc exploiter les champs ECS
produits par la collecte v3.

## Dashboards à utiliser

| Besoin | Dashboard Kibana | Jeux de données attendus | Indicateurs à suivre |
| --- | --- | --- | --- |
| Santé des hôtes | **[Metrics System] Overview** | `metrics-hostmetricsreceiver-*` | CPU (`system.cpu.utilization`), charge, mémoire (`system.memory.utilization`), filesystem, réseau, erreurs réseau et processus. |
| Santé du cluster | **[Kubernetes OTel] Overview**, **Nodes**, **Workloads**, **Pods** | `kubeletstatsreceiver.otel`, `k8sclusterreceiver.otel` | CPU/mémoire par pod et nœud, état du cluster, déploiements, conteneurs, volumes et capacité observée par `kubeletstats`/`k8s_cluster`. |
| Brokers et consommateurs | **[Metrics Kafka] Overview** | `metrics-kafka-*` | Brokers, partitions, réplication, lag et consumer groups. |
| Logs Kafka | **[Logs Kafka] Overview** | `logs-kafka.log-*` | Événements broker, contrôleur, changements d'état et erreurs Kafka. |
| Réplication MongoDB | **[Metrics MongoDB] Overview** | `metrics-mongodb-*` | Connexions, opérations, mémoire, cache et stockage ; les indicateurs de réplication `replstatus` nécessitent un replica set, alors que le POC utilise un MongoDB standalone. |
| Logs MongoDB | **[Logs MongoDB] Overview** | `logs-mongodb.log-*` | Logs `mongod`, erreurs, démarrage et événements du serveur. |
| Base PostgreSQL | **[Metrics PostgreSQL] Database Overview** | `metrics-postgresql-*` | Sessions, taille, cache, checkpoints et requêtes. |
| Logs PostgreSQL | **[Logs PostgreSQL] Overview**, **Query Duration Overview** | `logs-postgresql.log-*`, `metrics-postgresql.statement-*` | Logs PostgreSQL et durée des requêtes ; `pg_stat_statements` doit être chargé dans PostgreSQL. |
| Services applicatifs | Observability > APM > Services et Discover | `apm.service_transaction.1m`, `apm.transaction.1m`, `apm.app.*`, `metrics-prometheusreceiver.otel-*`, traces APM/OTLP | Débit, latence p50/p95/p99, taux d'erreur, dépendances, traces et métriques Actuator scrappées. |
| Métriques métier | **Métriques métier — Supermarket Demo** | `metrics-prometheusreceiver.otel-*` | Commandes finalisées, réassorts demandés/terminés et ventilation des commandes par canal. |
| SLA pains achetés | **Observability > SLOs** et **Alerts and Insights > Rules** | `logs-*` | SLO à 99 % de périodes de 24 heures conformes sur 30 jours, avec au moins 10 pains `BREAD-WHOLE` achetés par période ; alerte sur les dernières 24 heures. |
| Santé de la collecte | Logs de `elastic-agent`, état Fleet et consumer lag Kafka | journaux systemd, état Fleet et état des groupes Kafka | Agents Fleet healthy sur `poc-01`, `otel-backend-01` et `otel-edge-01`, absence d'erreurs d'export et débit des topics applicatifs/Kubernetes. |
| Fiabilité des Collectors | **Alerts** et, avec une licence Platinum, SLO Kibana | `metrics-prometheusreceiver.otel-*` | Échecs d'export, queue backend proche de la saturation et scrape Actuator indisponible. |

Les métriques Prometheus des applications sont scrappées par jobs distincts (`order-service`, `inventory-service` et `restock-service`) afin que les courbes techniques et les tableaux puissent conserver une série par microservice.

Les métriques OTel Kubernetes sont consultables dans les dashboards **[Kubernetes OTel]**
installés par le package `kubernetes_otel`. Les dashboards classiques **[Metrics Kubernetes]**
attendent le schéma de l’Elastic Agent Kubernetes autonome et ne sont pas alimentés par
le flux `kubeletstats` de cette architecture.

Le package Fleet `kubernetes_otel` installe onze dashboards Kubernetes OTel avec des requêtes ES|QL
embarquées. `make kibana-fleet-config-deploy` les réconcilie avec le schéma v3 :
les panneaux de redémarrages, utilisation mémoire et utilisation des limites sont
calculés à partir des champs réellement indexés par `kubeletstats` et `k8s_cluster`.
La revue peut être rejouée séparément avec `make kubernetes-otel-dashboards-deploy`,
puis contrôlée avec `make kubernetes-otel-dashboards-verify`.

Les métriques doivent être filtrées par environnement (`deployment.environment.name`),
service (`service.name`) et hôte (`host.name`) avant d'interpréter une alerte.
Pour ce POC, PostgreSQL est attendu uniquement sur `poc-01`; le dashboard ne
doit afficher les métriques PostgreSQL de `poc-01`.

## Déploiement et vérification

Déployer la configuration déclarative des intégrations Fleet :

```bash
make kubernetes-validate
make kibana-fleet-config-deploy
make business-dashboard-deploy
make observability-policies-deploy
```

Vérifier ensuite que les sources de tous les dashboards ont publié des
documents sur les quinze dernières minutes :

```bash
make dashboards-verify
```

La cible n'affiche aucun secret et vérifie les data streams attendus ainsi que
les métriques clés ci-dessus. Elle vérifie aussi les onze dashboards Kubernetes
OTel et leurs références de champs. Elle permet de distinguer un dashboard vide
d'un problème de collecte.

Le dashboard versionné est supprimé puis réimporté par `make business-dashboard-deploy`
(ou automatiquement par `make elk-deploy`). Le script
`platform/elk/scripts/replace-kibana-dashboard.sh` automatise cette séquence ;
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

La vue inclut également quatre panneaux de santé applicative : disponibilité
(`metrics.up`), tendances CPU et mémoire JVM, puis surcharge GC. Ces indicateurs
sont calculés sur la période sélectionnée et peuvent être vides si le flux de
métriques applicatives n'est pas alimenté.

L'ordre visuel regroupe les panneaux par parcours de lecture : indicateurs et
graphiques métier, stock, trafic HTTP entrant et sortant, traitements Kafka,
puis disponibilité et saturation JVM. Les liens vers APM terminent le dashboard.

Les filtres KQL doivent conserver une expression entre parenthèses. Une
expression générée avec un groupe vide (`and ()metrics...`) est invalide ; la
forme équivalente correcte est par exemple :
`data_stream.dataset:"prometheusreceiver.otel" and (metrics.business_orders_completed_total:* or metrics.business_stock_restock_requested_total:* or metrics.business_stock_restock_completed_total:*)`.
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
