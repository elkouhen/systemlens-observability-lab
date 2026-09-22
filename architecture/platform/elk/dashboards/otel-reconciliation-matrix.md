# Comparaison des dashboards OTel

Les dashboards OTel sont installés par les packages Fleet et leurs objets
initiaux ne sont pas exportés dans ce dépôt. La comparaison a donc été faite
entre les objets Saved Objects déployés dans Kibana, les champs du mapping
Elasticsearch et les métriques réellement reçues.

| Dashboard / panneau initial | Écart observé | Correction réconciliée |
| --- | --- | --- |
| MongoDB OTel — filtre `Server` | `attributes.mongodb.instance` absent du mapping OTel | `resource.attributes.server.address` |
| PostgreSQL OTel — panneaux de tuples, verrous et fichiers temporaires | Champs du schéma PostgreSQL classique absents (`postgresql.tup_*`, `postgresql.database.locks`, `postgresql.temp_*`) | Métriques réellement exposées par `postgresqlreceiver.otel` |
| PostgreSQL OTel — dimensions I/O | `attributes.source` et `attributes.type` absents des métriques PostgreSQL | `resource.attributes.postgresql.database.name` |
| PostgreSQL OTel — séries temporelles | Accessors Lens hérités des panneaux initiaux et colonnes incohérentes avec les résultats ES\|QL | Accessors, types et dimensions reconstruits depuis les colonnes ES\|QL |
| PostgreSQL OTel — `Database Size Gauge` | `postgresql.db_size` est une taille absolue, mais le panneau était formaté en pourcentage | `Connection Utilization Gauge` calculé par `backends / connection.max`, borné de 0 à 1 |

## Script unique

La réconciliation complète se lance avec :

```bash
make otel-dashboards-reconcile
```

La cible appelle
`platform/elk/scripts/reconcile-otel-dashboards.sh`, qui applique dans l'ordre
les contrôles, les requêtes ES|QL/Lens et les libellés. Chaque mise à jour réussie
est inscrite dans
`platform/elk/dashboards/reconciliation-history.md` sans enregistrer de secret.

Après la réconciliation, contrôler les objets et leurs données avec :

```bash
make postgresql-otel-dashboards-verify
make dashboards-verify
```
