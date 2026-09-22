# Journal des réconciliations Kibana

Ce journal ne contient ni mot de passe ni réponse complète de l'API Kibana.
Les prochaines exécutions des scripts de réconciliation ajoutent une ligne
après chaque mise à jour réussie. Le chemin peut être redéfini avec
`DASHBOARD_RECONCILIATION_LOG`.

| Horodatage UTC | Dashboard | Opération | Résultat |
| --- | --- | --- | --- |
| 2026-09-22 | `postgresql_otel-*` | Réconciliation des contrôles, requêtes ES\|QL et libellés PostgreSQL OTel | OK |
| 2026-09-22 | `mongodb_otel-overview`, `mongodb_otel-capacity`, `mongodb_otel-operations` | Remplacement du filtre invalide `attributes.mongodb.instance` par `resource.attributes.server.address` | OK |
| 2026-09-22 | `postgresql_otel-io-health` | Remplacement des dimensions absentes `attributes.source` et `attributes.type` par la base PostgreSQL | OK |
| 2026-09-22 | `postgresql_otel-overview`, `postgresql_otel-workload`, `postgresql_otel-locks`, `postgresql_otel-io-health` | Réparation des accessors Lens et du gauge d'utilisation des connexions | OK |
| 2026-09-22T09:30:48Z | `postgresql_otel-overview` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:30:49Z | `postgresql_otel-workload` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:30:50Z | `postgresql_otel-connections` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:30:51Z | `postgresql_otel-locks` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:30:52Z | `postgresql_otel-query-performance` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:30:53Z | `postgresql_otel-active-queries` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:30:54Z | `postgresql_otel-io-health` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:30:55Z | `mongodb_otel-overview` | `contrôle Serveur MongoDB OTel` | `OK` |
| 2026-09-22T09:30:56Z | `mongodb_otel-capacity` | `contrôle Serveur MongoDB OTel` | `OK` |
| 2026-09-22T09:30:57Z | `mongodb_otel-operations` | `contrôle Serveur MongoDB OTel` | `OK` |
| 2026-09-22T09:30:59Z | `postgresql_otel-overview` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:00Z | `postgresql_otel-workload` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:01Z | `postgresql_otel-connections` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:02Z | `postgresql_otel-locks` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:04Z | `postgresql_otel-query-performance` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:05Z | `postgresql_otel-active-queries` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:07Z | `postgresql_otel-io-health` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:08Z | `postgresql_otel-overview` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:09Z | `postgresql_otel-workload` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:10Z | `postgresql_otel-connections` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:11Z | `postgresql_otel-locks` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:12Z | `postgresql_otel-query-performance` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:13Z | `postgresql_otel-active-queries` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:31:14Z | `postgresql_otel-io-health` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:11Z | `postgresql_otel-overview` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:37:12Z | `postgresql_otel-workload` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:37:13Z | `postgresql_otel-connections` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:37:14Z | `postgresql_otel-locks` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:37:15Z | `postgresql_otel-query-performance` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:37:16Z | `postgresql_otel-active-queries` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:37:17Z | `postgresql_otel-io-health` | `contrôles OTel PostgreSQL` | `OK` |
| 2026-09-22T09:37:18Z | `mongodb_otel-overview` | `contrôle Serveur MongoDB OTel` | `OK` |
| 2026-09-22T09:37:19Z | `mongodb_otel-capacity` | `contrôle Serveur MongoDB OTel` | `OK` |
| 2026-09-22T09:37:20Z | `mongodb_otel-operations` | `contrôle Serveur MongoDB OTel` | `OK` |
| 2026-09-22T09:37:22Z | `postgresql_otel-overview` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:23Z | `postgresql_otel-workload` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:24Z | `postgresql_otel-connections` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:25Z | `postgresql_otel-locks` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:26Z | `postgresql_otel-query-performance` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:27Z | `postgresql_otel-active-queries` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:28Z | `postgresql_otel-io-health` | `requêtes ES\|QL et configuration Lens PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:29Z | `postgresql_otel-overview` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:30Z | `postgresql_otel-workload` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:31Z | `postgresql_otel-connections` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:32Z | `postgresql_otel-locks` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:33Z | `postgresql_otel-query-performance` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:34Z | `postgresql_otel-active-queries` | `libellés et description PostgreSQL OTel` | `OK` |
| 2026-09-22T09:37:35Z | `postgresql_otel-io-health` | `libellés et description PostgreSQL OTel` | `OK` |
