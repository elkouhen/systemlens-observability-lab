# Dashboards Kibana

Les fichiers `.ndjson` sont des exports d'objets sauvegardés Kibana. La
collecte v3 des VM est assurée par Elastic Agent Fleet et envoyée directement à
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

Le dashboard versionné est importé par `make business-dashboard-deploy` (ou
automatiquement par `make elk-deploy`). Il apparaît dans Kibana sous
**Métriques métier — Supermarket Demo**. Les panneaux utilisent le maximum du
compteur cumulatif dans chaque intervalle ; le filtre temporel Kibana doit donc
être positionné sur une période où les métriques sont présentes.

Le dashboard contient deux histogrammes temporels Kibana natifs : commandes
finalisées par heure et réassorts demandés/terminés par heure. L'axe horizontal
est l'heure et l'axe vertical le nombre cumulé ; le dashboard ne dépend pas
d'un panneau de logs ou d'une table de recherche.

## Documentation externe

- [Importer et exporter des objets sauvegardés Kibana](https://www.elastic.co/docs/explore-analyze/visualize/kibana/management)
- [Créer des dashboards Kibana](https://www.elastic.co/docs/explore-analyze/dashboards)
