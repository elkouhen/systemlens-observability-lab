# PostgreSQL avec Elastic Agent Fleet

La VM `data-01` collecte PostgreSQL localement avec l'intégration Fleet
`postgresql`. Les métriques sont envoyées directement vers Elasticsearch.

| Famille | Métriques attendues |
| --- | --- |
| Activité | `postgresql.backends`, `postgresql.operations`, `postgresql.commits`, `postgresql.rollbacks` |
| Bases | `postgresql.database.count`, `postgresql.db_size`, blocs lus, lignes |
| Objets | tables, index, scans et tailles |
| Écriture | buffers, checkpoints et WAL selon les droits et la version PostgreSQL |

Dans Discover, utiliser `data_stream.dataset: postgresql.otel` et
`host.name: data-01`. La collecte des requêtes détaillées n'est pas activée
par défaut ; elle nécessite notamment `pg_stat_statements` et des droits
adaptés.

Vérification reproductible :

```bash
source ./platform/elk/scripts/load-credentials.sh
make dashboards-verify
```
