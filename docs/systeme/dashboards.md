# Matrice des dashboards

Cette matrice est le point de départ de la recette. Elle sera enrichie à chaque
dashboard ou visualisation ajoutée. Une ligne décrit une attente vérifiable, pas
seulement un écran Kibana.

| Dashboard / vue | Données attendues | Data view / data stream | Champs ou dimensions clés | Contrôle minimal | Diagnostic prioritaire |
| --- | --- | --- | --- | --- | --- |
| Observability > APM > Services | les services applicatifs émetteurs et consommateurs, débit, latence et erreurs | `traces-*`, `metrics-*` | `service.name`, `trace.id`, durée, résultat transactionnel | générer un appel HTTP, puis attendre le traitement Kafka | gateway, topic `otel-traces`, backend OTel, fenêtre temporelle |
| Observability > APM > Traces | traces distribuées HTTP et Kafka ; transactions et spans corrélés | `traces-*` | `trace.id`, `span.id`, parent, `service.name`, type/protocole | ouvrir une trace depuis une transaction | propagation `traceparent`, noms des spans, indexation des spans |
| Observability > Infrastructure > Hosts | VM OpenTelemetry, VM Elastic Agent et VM Beats, avec CPU, mémoire, disque et réseau | `metrics-*` | `host.name`, `metrics.system.cpu.utilization`, `system.memory.utilization` | filtrer chaque rôle de VM dans Discover | EDOT sur la VM OpenTelemetry ; Metricbeat sur la VM Beats ; policy System sur la VM Elastic Agent |
| Logs Kubernetes | logs récents des deux services, avec métadonnées pod et corrélation trace | `logs-*` | `kubernetes.*`, `service.name`, `trace.id`, `span.id` | appeler un endpoint puis filtrer le pod | DaemonSet `kubernetes-logs`, RBAC, montage `/var/log` |
| Intégration MongoDB | 3 membres, replica set, primary, connexions, opérations et stockage | `metrics-mongodb.*`, `logs-mongodb.*` | `host.name`, état replica, `service.address` | `cluster-status.sh`, puis fenêtre 60 s | Agent Fleet, accès local MongoDB, policy `mongodb-fleet` |
| Intégration Kafka | brokers, partitions, groupes, JVM, réseau et réplication | `metrics-kafka.*`, `logs-kafka.*` | `host.name`, broker, topic, partition, métriques Jolokia | vérifier Jolokia local et le quorum | les métriques JMX détaillées ne sont aujourd'hui couvertes que par la VM Elastic Agent ; qualifier l'équivalent OTel |
| Intégration PostgreSQL | activité de l'hôte PostgreSQL, bgwriter, taille de base et logs | `metrics-postgresql.*`, `logs-postgresql.*` | `host.name`, base, connexions, bgwriter | requête applicative puis Discover | Agent Fleet, conteneur PostgreSQL, condition d'hôte dédiée |

## Méthode de recette commune

1. Choisir une période couvrant au moins deux intervalles de collecte.
2. Vérifier le document brut dans Discover avec le data view exact.
3. Vérifier que les champs de la colonne « Champs ou dimensions clés » sont
   présents et ont la valeur attendue.
4. Ouvrir ensuite le dashboard sans filtre résiduel incompatible.
5. Si le dashboard est vide mais que le document existe, comparer son filtre et
   son agrégation aux noms et types de champs indexés.

Les requêtes exactes, identifiants des visualisations et captures de référence
seront ajoutés par dashboard lors de leur qualification.

## Requêtes de vérification initiales

Ces requêtes KQL sont des points de départ dans Discover ; elles ne remplacent
pas les filtres et agrégations propres à chaque dashboard. Sélectionner d'abord
la période couvrant au moins deux intervalles de collecte.

| Vue | Data view | Requête KQL de départ | Résultat attendu |
| --- | --- | --- | --- |
| APM Services / Traces | `traces-*` | `service.name : ("order-service" or "inventory-service")` | documents récents des deux services après génération de trafic |
| Infrastructure > Hosts | `metrics-*` | `host.name : *` | une série par hôte ayant publié des métriques récentes |
| Logs Kubernetes | `logs-*` | `kubernetes.namespace : "supermarket-demo"` | événements des pods applicatifs avec `kubernetes.*` |
| MongoDB | `metrics-mongodb.*` | `event.dataset : "mongodb.replstatus"` | relevé replica set récent par hôte collecté |
| Kafka | `metrics-kafka.*` | `host.name : *` | documents de broker récents ; affiner ensuite par champ Kafka disponible |
| PostgreSQL | `metrics-postgresql.*` | `service.name : "postgresql"` | métriques récentes produites par EDOT sur la VM OpenTelemetry |

Les guides [vérifier un signal](how-to/verifier-un-signal.md) et
[diagnostiquer un dashboard vide](how-to/diagnostiquer-dashboard-vide.md)
transforment cette recette en étapes reproductibles.
