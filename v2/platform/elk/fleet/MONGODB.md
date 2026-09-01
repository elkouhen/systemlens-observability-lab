# MongoDB avec EDOT Agent

Ce guide décrit la collecte MongoDB v2 par EDOT Agent. La package policy
MongoDB déclarée dans
[`../../kubernetes/base/observability/kibana.yaml`](../../kubernetes/base/observability/kibana.yaml).
`kibana.yaml` reste disponible pour la configuration Fleet de la plateforme,
mais n'est pas le chemin actif de la VM v2. `make fleet-sync` n'est pas
nécessaire à cette collecte.

## Chemin des données

```text
EDOT Agent de data-01
  └─ receiver mongodb : localhost:27017
       └─ dbStats, serverStatus, opérations, connexions, stockage
            ↓
       otel-metrics → Kafka → EDOT Collector backend → metrics-mongodb.otel-* → Kibana
```

Le choix de `localhost:27017` est intentionnel : l'Agent partage l'hôte de
MongoDB. `host.name` distingue ce membre des autres profils de collecte.

## Lire la configuration

1. Le receiver `mongodb` est déclaré dans `v2/ansible/templates/otel-agent.yml.j2`
   et s'exécute localement sur la VM ; aucun enrôlement Fleet n'est requis pour
   cette collecte.
2. Le receiver `filelog/vm` collecte les logs MongoDB locaux, sans Filebeat
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

Les documents sont écrits dans `metrics-mongodb.otel-*`. Rechercher
`data_stream.dataset: mongodb.otel` dans Discover, puis utiliser `host.name`
pour isoler le membre.

## Adapter à un autre environnement

| Besoin | Modification à faire |
| --- | --- |
| Agent hors de l'hôte MongoDB | remplacer `hosts` par une URI MongoDB accessible depuis l'Agent |
| MongoDB distant | remplacer `localhost:27017` par l'URI accessible depuis l'Agent |
| Authentification | fournir un utilisateur de supervision ; ne jamais committer son mot de passe dans le JSON |
| TLS | activer TLS et fournir la CA par le mécanisme de secrets/variables Fleet adapté à l'environnement |
| Moins de charge | augmenter `period` au-delà de `60s` |
| Logs via Fleet | non utilisé dans le chemin v2 ; ne jamais activer une source Filebeat équivalente |

L'utilisateur MongoDB doit disposer des droits nécessaires aux commandes de
supervision. Le rôle intégré `clusterMonitor` couvre notamment les commandes
utilisées par les streams de métriques ; `dbstats` et `replstatus` demandent en
plus les droits détaillés par l'intégration officielle.

## Vérification et dépannage

1. Vérifier localement `mongosh` et l'écoute sur `localhost:27017` depuis la VM.
2. Dans Discover, filtrer `data_stream.dataset: mongodb.otel` et vérifier un
   événement récent pour `host.name: data-01`.
3. En cas d'erreur d'autorisation, corriger le rôle MongoDB utilisé par EDOT.
4. En cas d'absence de métriques, consulter `journalctl -u poc-otel-agent`.

## Documentation officielle

- [Intégration MongoDB Elastic](https://www.elastic.co/docs/reference/integrations/mongodb)
- [Métrique MongoDB `replstatus`](https://www.elastic.co/docs/reference/beats/metricbeat/metricbeat-metricset-mongodb-replstatus)
- [Policies Elastic Agent](https://www.elastic.co/docs/reference/fleet/agent-policy)
