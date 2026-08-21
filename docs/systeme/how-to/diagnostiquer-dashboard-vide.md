# Diagnostiquer un dashboard vide

Ce guide résout le cas où une vue Kibana n'affiche aucune donnée attendue. Il
part du document brut vers le dashboard afin d'éviter de modifier une
visualisation alors que la collecte est en panne.

## 1. Écarter les filtres les plus fréquents

Dans le dashboard, élargir la période à au moins deux intervalles de collecte,
retirer provisoirement les filtres globaux et noter le data view utilisé. Ne
sauvegardez pas ces modifications temporaires.

## 2. Chercher un document brut dans Discover

Ouvrir le même data view et commencer par une requête courte :

| Cas | Data view | Requête KQL de départ |
| --- | --- | --- |
| traces applicatives | `traces-*` | `service.name : ("order-service" or "inventory-service")` |
| logs Kubernetes | `logs-*` | `kubernetes.namespace : "supermarket-demo"` |
| hôtes | `metrics-*` | `host.name : *` |
| MongoDB | `metrics-mongodb.*` | `event.dataset : "mongodb.replstatus"` |
| PostgreSQL | `metrics-postgresql.*` | `service.name : "postgresql"` |

S'il n'existe aucun document récent, le dashboard n'est pas encore le bon
niveau de diagnostic : suivre [Vérifier un signal de bout en bout](verifier-un-signal.md).

## 3. Comparer le document au besoin du dashboard

Si le document existe, comparer son nom, son type et sa valeur avec les champs
requis dans la [matrice des dashboards](../dashboards.md). Vérifier notamment
`host.name`, `service.name`, `trace.id`, le data stream et l'horodatage. Les
métriques OpenTelemetry conservent parfois des attributs de ressource en plus
des champs ECS attendus par des visualisations historiques.

## 4. Isoler le filtre ou l'agrégation fautive

Ajouter les filtres du dashboard un par un dans Discover. Le premier filtre qui
fait disparaître les documents identifie le décalage. Si les documents restent
visibles, comparer l'agrégation et le type du champ dans la visualisation : un
champ numérique, une date ou un mot-clé ne s'agrègent pas de la même manière.

Consigner la requête validée et l'identifiant de la visualisation dans la ligne
de recette concernée. Cela transforme une correction ponctuelle en procédure
réutilisable.
