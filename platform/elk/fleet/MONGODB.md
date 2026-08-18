# MongoDB dans Fleet

Ce guide explique la package policy MongoDB déclarée dans
[`../kubernetes/kibana-fleet-patch.yaml`](../kubernetes/kibana-fleet-patch.yaml).
Elle observe le replica set MongoDB du POC depuis un Elastic Agent installé sur
chacune des VM `data-01` à `data-03`. Le JSON voisin reste un modèle pour le
cas optionnel des policies Ansible par VM.

## Chemin des données

```text
Elastic Agent sur data-0N
  └─ MongoDB local : localhost:27017
       ├─ collstats, dbstats, metrics, status
       └─ replstatus
            ↓
       metrics-mongodb.*-default → Elasticsearch → Kibana
```

Le choix de `localhost:27017` est intentionnel : l'Agent partage l'hôte de
MongoDB. La policy est donc réutilisable sur les trois VM, tout en conservant
`host.name` pour distinguer les membres du replica set.

## Lire la policy

1. `policy_ids: ["mongodb-hosts"]` rattache l'intégration à l'agent policy
   créée par `sync-fleet-policies.sh`. Un Agent ne reçoit la configuration que
   s'il est enrôlé dans cette policy.
2. L'entrée `logfile` est désactivée. Les logs MongoDB passent déjà par
   Filebeat : l'activer ici créerait des doublons dans `logs-mongodb.log-*`.
3. L'entrée `mongodb/metrics` utilise `localhost:27017` et un intervalle de
   60 secondes pour chaque stream.
4. `ssl.enabled: false` convient seulement au POC local. Ce réglage doit être
   revu dès que MongoDB expose TLS.

## Ce que mesure chaque stream

| Data stream | Ce qu'il permet de diagnostiquer |
| --- | --- |
| `mongodb.collstats` | opérations et temps par collection |
| `mongodb.dbstats` | taille et stockage par base |
| `mongodb.metrics` | connexions, mémoire et activité du serveur |
| `mongodb.replstatus` | rôle primary/secondary, lag et fenêtre d'oplog |
| `mongodb.status` | état global renvoyé par `serverStatus` |

Les documents sont écrits dans des data streams de la forme
`metrics-mongodb.<dataset>-default`. Rechercher d'abord
`data_stream.dataset: mongodb.replstatus` dans Discover pour valider le
replica set, puis utiliser `host.name` et `service.address` pour isoler un
membre.

## Adapter à un autre environnement

| Besoin | Modification à faire |
| --- | --- |
| Agent hors de l'hôte MongoDB | remplacer `hosts` par une URI MongoDB accessible depuis l'Agent |
| Replica set distant | utiliser une URI avec tous les membres et `replicaSet=<nom>` |
| Authentification | fournir un utilisateur de supervision ; ne jamais committer son mot de passe dans le JSON |
| TLS | activer TLS et fournir la CA par le mécanisme de secrets/variables Fleet adapté à l'environnement |
| Moins de charge | augmenter `period` au-delà de `60s` |
| Logs via Fleet | activer `logfile` **après** avoir désactivé la source Filebeat équivalente |

L'utilisateur MongoDB doit disposer des droits nécessaires aux commandes de
supervision. Le rôle intégré `clusterMonitor` couvre notamment les commandes
utilisées par les streams de métriques ; `dbstats` et `replstatus` demandent en
plus les droits détaillés par l'intégration officielle.

## Vérification et dépannage

1. Dans Kibana > Fleet, vérifier que l'Agent est `Healthy` et qu'il a reçu la
   policy `mongodb-hosts`.
2. Vérifier localement `mongosh` et l'écoute sur `localhost:27017` depuis la VM.
3. Dans Discover, filtrer `data_stream.dataset: mongodb.status` et vérifier un
   événement récent pour chaque `host.name`.
4. En cas d'erreur d'autorisation, corriger le rôle MongoDB, pas la policy
   Fleet : les échecs de commande sont visibles dans les logs Elastic Agent.
5. En cas d'absence de `replstatus`, vérifier le nom et l'état du replica set,
   ainsi que l'accès à la base `local`.

## Documentation officielle

- [Intégration MongoDB Elastic](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Métrique MongoDB `replstatus`](https://www.elastic.co/docs/reference/beats/metricbeat/metricbeat-metricset-mongodb-replstatus)
- [Policies Elastic Agent](https://www.elastic.co/docs/reference/fleet/agent-policy)
