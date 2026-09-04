# Dashboards Kibana

Les fichiers `.ndjson` sont des exports d'objets sauvegardés Kibana. Le fichier
`business-metrics-dashboard.json` est une définition inline de l'API Dashboard
Kibana, avec des visualisations ES|QL. La collecte v3 des VM est assurée par Elastic Agent Fleet et envoyée directement à
Elasticsearch. Les packages Fleet de plateforme déclarés dans
[`platform/kubernetes/base/observability/kibana.yaml`](../../kubernetes/base/observability/kibana.yaml).
Les dashboards Fleet classiques peuvent donc exploiter les champs ECS
produits par la collecte v3.

## Dashboards à utiliser

| Besoin | Dashboard Kibana | Jeux de données attendus | Indicateurs à suivre |
| --- | --- | --- | --- |
| Santé des hôtes | **[Metrics System] Overview** | `metrics-hostmetricsreceiver-*` | CPU, charge, mémoire, filesystem, réseau, erreurs réseau et processus. |
| Santé du cluster | **[Metrics Kubernetes] Cluster Overview**, **Nodes**, **Deployments**, **Pods** | `kubernetes.container`, `kubernetes.pod`, `kubernetes.state_*` | CPU/mémoire par pod et nœud, pods non prêts, redémarrages, réplicas souhaités/disponibles, capacité des volumes. |
| Brokers et consommateurs | **[Metrics Kafka] Overview** | `metrics-kafka-*` | Brokers, partitions, réplication, lag et consumer groups. |
| Réplication MongoDB | **[Metrics MongoDB] Overview** | `metrics-mongodb-*` | Réplication, connexions, opérations, stockage et latence. |
| Base PostgreSQL | **[Metrics PostgreSQL] Database Overview** | `metrics-postgresql-*` | Sessions, taille, cache, checkpoints et requêtes. |
| Services applicatifs | Observability > APM > Services et Discover | `apm.service_transaction.1m`, `apm.transaction.1m`, `apm.app.*`, `metrics-prometheusreceiver.otel-*`, traces APM/OTLP | Débit, latence p50/p95/p99, taux d'erreur, dépendances, traces et métriques Actuator scrappées. |
| Métriques métier | **Métriques métier — Supermarket Demo** | `metrics-prometheusreceiver.otel-*` | Commandes finalisées, réassorts demandés/terminés et ventilation des commandes par canal. |
| Santé de la collecte | Logs de `elastic-agent`, état Fleet et consumer lag Kafka | journaux systemd, état Fleet et état des groupes Kafka | Agent Fleet healthy sur `data-01`, absence d'erreurs d'export et débit des topics applicatifs/Kubernetes. |

Les métriques Prometheus des applications sont scrappées par jobs distincts (`order-service`, `inventory-service` et `restock-service`) afin que les courbes techniques et les tableaux puissent conserver une série par microservice.

Les métriques doivent être filtrées par environnement (`deployment.environment.name`),
service (`service.name`) et hôte (`host.name`) avant d'interpréter une alerte.
Pour ce POC, PostgreSQL est attendu uniquement sur `data-01`; le dashboard ne
doit afficher les métriques PostgreSQL de `data-01`.

## Déploiement et vérification

Déployer la configuration déclarative des intégrations Fleet :

```bash
make kubernetes-validate
make kibana-fleet-config-deploy
make business-dashboard-deploy
```

Vérifier ensuite que les sources de tous les dashboards ont publié des
documents sur les quinze dernières minutes :

```bash
make dashboards-verify
```

La cible n'affiche aucun secret et vérifie les data streams attendus ainsi que
les métriques clés ci-dessus. Elle permet de distinguer un dashboard vide
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

La vue inclut également six panneaux de santé applicative : disponibilité
(`metrics.up`), CPU, ratio de mémoire JVM et threads actifs, avec les tendances
CPU et mémoire. Ces indicateurs sont calculés sur la période sélectionnée et
peuvent être vides si le flux de métriques applicatives n'est pas alimenté.

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

## Documentation externe

- [Importer et exporter des objets sauvegardés Kibana](https://www.elastic.co/docs/explore-analyze/visualize/kibana/management)
- [Créer des dashboards Kibana](https://www.elastic.co/docs/explore-analyze/dashboards)
