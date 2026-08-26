# Dashboards Kibana

Les fichiers `.ndjson` sont des exports d'objets sauvegardés Kibana. Les
dashboards de supervision courante sont fournis et maintenus par les packages
Fleet déclarés dans
[`platform/kubernetes/base/observability/kibana.yaml`](../../kubernetes/base/observability/kibana.yaml).
Ils sont donc recréés lors du déploiement de la configuration Kibana/Fleet,
sans export manuel à versionner.

## Dashboards à utiliser

| Besoin | Dashboard Kibana | Jeux de données attendus | Indicateurs à suivre |
| --- | --- | --- | --- |
| Santé des hôtes | **[Metrics System] Overview** | `system.cpu`, `system.memory`, `system.filesystem`, `system.network` | CPU et charge, mémoire utilisée, saturation des volumes, débit et erreurs réseau, processus. |
| Santé du cluster | **[Metrics Kubernetes] Cluster Overview**, **Nodes**, **Deployments**, **Pods** | `kubernetes.container`, `kubernetes.pod`, `kubernetes.state_*` | CPU/mémoire par pod et nœud, pods non prêts, redémarrages, réplicas souhaités/disponibles, capacité des volumes. |
| Brokers et consommateurs | **[Metrics Kafka] Overview** | `kafka.broker`, `kafka.partition`, `kafka.consumergroup` | Brokers et contrôleurs actifs, partitions sous-répliquées, taille/lag des consumer groups, trafic réseau et JVM. |
| Réplication MongoDB | **[Metrics MongoDB] Overview** et **SystemLens · MongoDB clusters** | `mongodb.status`, `mongodb.metrics`, `mongodb.replstatus`, `mongodb.collstats` | Primary/secondary, état du replica set, connexions, opérations, stockage et latence. |
| Base PostgreSQL | **[Metrics PostgreSQL] Database Overview** | `postgresql.activity`, `postgresql.database`, `postgresql.bgwriter`, `postgresql.statement` | Sessions actives/bloquées, taille et croissance, cache, écritures/checkpoints et requêtes coûteuses. |
| Services applicatifs | Observability > APM > Services | `apm.service_transaction.1m`, `apm.transaction.1m`, `apm.app.*`, traces APM/OTLP | Débit, latence p50/p95/p99, taux d'erreur, dépendances, traces et métriques JVM. |
| Santé de la collecte | **[Elastic Agent] Agent metrics** et Fleet > Agents | `elastic_agent.*` | Agents sains, erreurs d'input, débit d'événements et retards de collecte. |

Les métriques doivent être filtrées par environnement (`service.environment`),
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

La cible n'affiche aucun secret et échoue en signalant précisément le jeu de
données absent. Elle permet de distinguer un dashboard vide d'un problème de
collecte.

## Fichiers SystemLens

- `mongodb-cluster-primary.ndjson` : dashboard SystemLens du replica set
  MongoDB et de son primary.

Importer ce fichier avec `make dashboard-deploy`, ou sélectionner un autre
export NDJSON en argument de `platform/elk/scripts/deploy-kibana-dashboard.sh`.

## Documentation externe

- [Importer et exporter des objets sauvegardés Kibana](https://www.elastic.co/docs/explore-analyze/visualize/kibana/management)
- [Créer des dashboards Kibana](https://www.elastic.co/docs/explore-analyze/dashboards)
