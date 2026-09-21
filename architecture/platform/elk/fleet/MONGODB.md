# MongoDB avec l'agent EDOT standalone

Ce guide décrit la collecte MongoDB par Elastic Agent Fleet. La package policy
MongoDB reste documentée dans
[`../scripts/bootstrap-fleet-policies.sh`](../scripts/bootstrap-fleet-policies.sh)
comme asset de compatibilité. Le chemin actif est déclaré dans le template EDOT
Ansible et déployé par `make elastic-agent-vm-provision`.

## Chemin des données

```text
Elastic Agent EDOT standalone de poc-01
  └─ receiver mongodb : localhost:27017
       └─ dbStats, serverStatus, opérations, connexions, stockage
            ↓
       métriques MongoDB → Elasticsearch → Kibana
```

Le choix de `localhost:27017` est intentionnel : l'Agent partage l'hôte de
MongoDB. `host.name` distingue ce membre des autres profils de collecte.

## Lire la configuration

1. Le receiver `mongodb` est déclaré dans le template EDOT et s'exécute
   localement sur la VM, sans enrôlement Fleet.
2. Le receiver `filelog/system` collecte les logs MongoDB locaux, sans Filebeat
   concurrent.
3. Le receiver `mongodb` utilise `localhost:27017` et un intervalle de
   60 secondes pour chaque stream.
4. `ssl.enabled: false` convient seulement au POC local. Ce réglage doit être
   revu dès que MongoDB expose TLS.

## Ce que mesure chaque stream

| Data stream | Ce qu'il permet de diagnostiquer |
| --- | --- |
| Famille OTel | Indicateurs attendus |
| `mongodb.connection.*` | connexions et sessions |
| `mongodb.operation.*` | opérations, durée et compteurs |
| `mongodb.memory.*`, `mongodb.cache.*` | mémoire et cache |
| `mongodb.storage.*`, `mongodb.data.*` | stockage et taille des données |
| `mongodb.network.*`, `mongodb.cursor.*` | trafic, requêtes et curseurs |

Les documents sont écrits dans le data stream OTel
`metrics-mongodbreceiver.otel-default`. Rechercher
`data_stream.dataset: mongodbreceiver.otel`
dans Discover, puis utiliser `host.name`
pour isoler le membre.

## Adapter à un autre environnement

| Besoin | Modification à faire |
| --- | --- |
| Agent hors de l'hôte MongoDB | remplacer `hosts` par une URI MongoDB accessible depuis l'Agent |
| MongoDB distant | remplacer `localhost:27017` par l'URI accessible depuis l'Agent |
| Authentification | fournir un utilisateur de supervision ; ne jamais committer son mot de passe dans le JSON |
| TLS | activer TLS et fournir la CA par le mécanisme de secrets/variables Fleet adapté à l'environnement |
| Moins de charge | augmenter `period` au-delà de `60s` |
| Logs via Fleet | collectés par l'intégration `system`, sans Filebeat concurrent |

L'utilisateur MongoDB doit disposer des droits nécessaires aux commandes de
supervision. Le rôle intégré `clusterMonitor` couvre notamment les commandes
utilisées par les streams de métriques ; `dbstats` et `replstatus` demandent en
plus les droits détaillés par l'intégration officielle.

## Vérification et dépannage

1. Vérifier localement `mongosh` et l'écoute sur `localhost:27017` depuis la VM.
2. Dans Discover, filtrer `data_stream.dataset: mongodbreceiver.otel` et vérifier un
   événement récent pour `host.name: poc-01`.
3. En cas d'erreur d'autorisation, corriger le rôle MongoDB utilisé par EDOT.
4. En cas d'absence de métriques, vérifier l'état de l'Elastic Agent dans Fleet.

## Documentation officielle

- [Intégration MongoDB Elastic](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Métrique MongoDB `replstatus`](https://www.elastic.co/docs/reference/beats/metricbeat/metricbeat-metricset-mongodb-replstatus)
- [Policies Elastic Agent](https://www.elastic.co/docs/reference/fleet/agent-policy)
