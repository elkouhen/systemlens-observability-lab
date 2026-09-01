# Dashboards Kibana

Les fichiers `.ndjson` sont des exports d'objets sauvegardés Kibana. La
collecte v2 des VM est assurée par EDOT Agent ; les signaux sont relayés par
Kafka puis exportés par le Collector backend en mapping ECS. Les packages Fleet de plateforme déclarés dans
[`platform/kubernetes/base/observability/kibana.yaml`](../../kubernetes/base/observability/kibana.yaml).
Les dashboards Fleet classiques peuvent donc exploiter les champs ECS
produits par la collecte v2.

## Dashboards à utiliser

| Besoin | Dashboard Kibana | Jeux de données attendus | Indicateurs à suivre |
| --- | --- | --- | --- |
| Santé des hôtes | **[Metrics System] Overview** | `metrics-hostmetricsreceiver-*` | CPU, charge, mémoire, filesystem, réseau, erreurs réseau et processus. |
| Santé du cluster | **[Metrics Kubernetes] Cluster Overview**, **Nodes**, **Deployments**, **Pods** | `kubernetes.container`, `kubernetes.pod`, `kubernetes.state_*` | CPU/mémoire par pod et nœud, pods non prêts, redémarrages, réplicas souhaités/disponibles, capacité des volumes. |
| Brokers et consommateurs | **[Metrics Kafka] Overview** | `metrics-kafka-*` | Brokers, partitions, réplication, lag et consumer groups. |
| Réplication MongoDB | **[Metrics MongoDB] Overview** | `metrics-mongodb-*` | Réplication, connexions, opérations, stockage et latence. |
| Base PostgreSQL | **[Metrics PostgreSQL] Database Overview** | `metrics-postgresql-*` | Sessions, taille, cache, checkpoints et requêtes. |
| Services applicatifs | Observability > APM > Services | `apm.service_transaction.1m`, `apm.transaction.1m`, `apm.app.*`, traces APM/OTLP | Débit, latence p50/p95/p99, taux d'erreur, dépendances, traces et métriques JVM. |
| Santé de la collecte | Logs du service `observability-otel-agent`, métriques des Collectors et consumer lag Kafka | journaux systemd, métriques Collector et état des groupes Kafka | Agent EDOT actif sur `data-01`, absence d'erreurs de collecte/export, débit des topics et absence de lag durable. |

Les métriques doivent être filtrées par environnement (`deployment.environment.name`),
service (`service.name`) et hôte (`host.name`) avant d'interpréter une alerte.
Pour ce POC, PostgreSQL est attendu uniquement sur `data-01`; le dashboard ne
doit afficher les métriques PostgreSQL de `data-01`.

## Déploiement et vérification

Déployer la configuration déclarative des intégrations Fleet :

```bash
make kubernetes-validate
make kibana-fleet-config-deploy
```

Vérifier ensuite que les sources de tous les dashboards ont publié des
documents sur les quinze dernières minutes :

```bash
make dashboards-verify
```

La cible n'affiche aucun secret et vérifie les data streams attendus ainsi que
les métriques clés ci-dessus. Elle permet de distinguer un dashboard vide
d'un problème de collecte.

## Documentation externe

- [Importer et exporter des objets sauvegardés Kibana](https://www.elastic.co/docs/explore-analyze/visualize/kibana/management)
- [Créer des dashboards Kibana](https://www.elastic.co/docs/explore-analyze/dashboards)
