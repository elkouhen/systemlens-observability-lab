# Dashboards Kibana

Les fichiers `.ndjson` sont des exports d'objets sauvegardés Kibana. La
collecte v2 des VM est assurée par EDOT Agent ; elle produit donc des
data streams OTel natifs. Les packages Fleet déclarés dans
[`platform/kubernetes/base/observability/kibana.yaml`](../../kubernetes/base/observability/kibana.yaml).
La collecte v2 produit des data streams OTel natifs. Les dashboards Fleet
classiques attendent encore les datasets et champs ECS historiques ; ils ne
sont donc pas compatibles automatiquement avec cette collecte.

## Dashboards à utiliser

| Besoin | Dashboard Kibana | Jeux de données attendus | Indicateurs à suivre |
| --- | --- | --- | --- |
| Santé des hôtes | **[Metrics System] Overview** | `metrics-hostmetricsreceiver.otel-*` | CPU, charge, mémoire, filesystem, réseau, erreurs réseau et processus. Compatibilité ECS du dashboard classique non garantie. |
| Santé du cluster | **[Metrics Kubernetes] Cluster Overview**, **Nodes**, **Deployments**, **Pods** | `kubernetes.container`, `kubernetes.pod`, `kubernetes.state_*` | CPU/mémoire par pod et nœud, pods non prêts, redémarrages, réplicas souhaités/disponibles, capacité des volumes. |
| Brokers et consommateurs | **[Metrics Kafka] Overview** | `metrics-kafka.otel-*` | Brokers, partitions, réplication, lag et consumer groups. Le dashboard Fleet classique attend des champs ECS différents. |
| Réplication MongoDB | **[Metrics MongoDB] Overview** | `metrics-mongodb.otel-*` | Réplication, connexions, opérations, stockage et latence. Le dashboard Fleet classique attend des champs ECS différents. |
| Base PostgreSQL | **[Metrics PostgreSQL] Database Overview** | `metrics-postgresql.otel-*` | Sessions, taille, cache, checkpoints et requêtes. Le dashboard Fleet classique attend des champs ECS différents. |
| Services applicatifs | Observability > APM > Services | `apm.service_transaction.1m`, `apm.transaction.1m`, `apm.app.*`, traces APM/OTLP | Débit, latence p50/p95/p99, taux d'erreur, dépendances, traces et métriques JVM. |
| Santé de la collecte | **[Elastic Agent] Agent metrics**, Fleet > Agents et services Beats de `data-03` | `elastic_agent.*` et métriques Beats | Agents Fleet sains sur `data-01`/`data-02`, services Filebeat/Metricbeat actifs sur `data-03`, erreurs d'input, débit d'événements et retards de collecte. |

Les métriques doivent être filtrées par environnement (`deployment.environment.name`),
service (`service.name`) et hôte (`host.name`) avant d'interpréter une alerte.
Pour ce POC, PostgreSQL est attendu uniquement sur `data-01`; le dashboard ne
doit donc pas afficher de métriques PostgreSQL de `data-02`.

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

La cible n'affiche aucun secret et vérifie à la fois les data streams OTel et
les métriques clés ci-dessus. Elle permet de distinguer un dashboard vide
d'un problème de collecte.

## Documentation externe

- [Importer et exporter des objets sauvegardés Kibana](https://www.elastic.co/docs/explore-analyze/visualize/kibana/management)
- [Créer des dashboards Kibana](https://www.elastic.co/docs/explore-analyze/dashboards)
