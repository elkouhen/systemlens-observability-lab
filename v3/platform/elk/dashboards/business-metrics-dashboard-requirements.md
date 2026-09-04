# Besoins fonctionnels — dashboard des métriques

## Objectif

Le dashboard `Métriques métier — Supermarket Demo` doit permettre à un opérateur de parcourir les signaux dans l’ordre suivant : métier, stock, Traffic, Latency, Errors, puis Saturation. Les visualisations doivent respecter la période sélectionnée et rendre visibles les différences entre microservices.

## Ordre de lecture et correspondance Kibana

L’ordre ci-dessous est la référence commune avec la grille du dashboard :

1. **Métier** : commandes finalisées, réassorts demandés/terminés, écart, tendances et canaux.
2. **Stock** : état du stock par produit.
3. **Traffic** : volume HTTP entrant (`http-traffic-kpi`).
4. **Latency** : latence HTTP (`http-latency-kpi`), statistiques par endpoint, clients Kafka, traitement Kafka et appels HTTP sortants.
5. **Errors** : erreurs HTTP (`http-errors-kpi`) et disponibilité des services.
6. **Saturation** : CPU, mémoire JVM, threads, courbes CPU/RAM/GC, runtime JVM et pools d’exécution.
7. **Navigation** : liens APM et Kubernetes.

Les identifiants de panneaux indiqués dans la définition JSON sont la référence technique ; les intitulés ci-dessous décrivent leur comportement fonctionnel.

## Description des widgets

| Widget | Description fonctionnelle | Lecture attendue | Limites connues |
| --- | --- | --- | --- |
| Commandes finalisées | Affiche le nombre de commandes finalisées pendant la période. | Mesurer le volume métier traité. | Calculé à partir du delta des compteurs par instance et canal. |
| Réassorts demandés | Affiche le nombre de demandes de réassort créées. | Détecter une hausse des besoins de réapprovisionnement. | Dépend de la continuité des compteurs Prometheus. |
| Réassorts terminés | Affiche le nombre de réassorts exécutés. | Vérifier la capacité à absorber les demandes. | Ne mesure pas la durée d’un réassort. |
| Écart de réassorts | Compare les réassorts demandés et terminés. | Une valeur positive indique un retard à traiter. | Agrégé sur la période sélectionnée. |
| Commandes finalisées par période | Trace le volume de commandes dans le temps. | Identifier les périodes de charge et les ruptures d’activité. | Les canaux sont représentés par séries séparées. |
| Flux de réassort par période | Trace les demandes et exécutions de réassort dans le temps. | Comparer l’arrivée des demandes et leur traitement. | Repose sur des compteurs, pas sur des événements individuels. |
| Commandes par canal | Compare les commandes `rest` et `kafka`. | Vérifier la répartition des flux entrants. | Les libellés doivent rester distincts (`REST`, `Kafka`). |
| Traffic HTTP | Affiche le volume des séries de requêtes HTTP entrantes. | Mesurer le trafic reçu par les services. | Ce n’est pas un compteur de requêtes métier dédupliquées. |
| Statistiques clients Kafka | Agrège les latences de fetch consommateur, publication producteur, débit consommé et lag par client/topic/partition. | Suivre le trafic Kafka, la performance du client et le retard de consommation. | Ne mesure pas le temps d’exécution du code métier du consumer. |
| Latency HTTP | Affiche la moyenne des maxima de durée HTTP observés. | Détecter une dégradation de latence. | Les vrais P95/P99 ne sont pas encore indexés. |
| Statistiques HTTP par endpoint | Agrège les appels par service, méthode et endpoint avec volume, moyenne, maximum et taux d’erreur. | Identifier les endpoints prioritaires à optimiser. | P95/P99 indisponibles dans les champs actuels. |
| Temps de traitement des messages Kafka | Affiche P50, P95, P99 et maximum du traitement instrumenté par consumer et topic. | Mesurer la durée réelle du handler Kafka. | Les valeurs apparaissent après traitement et ingestion des histogrammes. |
| Appels HTTP sortants | Agrège les appels sortants par service, méthode et cible avec volume et latence. | Identifier les dépendances HTTP lentes ou sollicitées. | Les P95/P99 sortants ne sont pas disponibles. |
| Errors HTTP | Affiche le taux de réponses dont `outcome` vaut `SERVER_ERROR`. | Repérer les erreurs serveur. | Les erreurs clientes ou exceptions non mappées peuvent manquer. |
| Stock par produit | Affiche le stock courant par identifiant et nom de produit, trié du plus faible au plus élevé. | Repérer les produits proches de la rupture. | Nécessite que la jauge stock ait été publiée récemment. |
| CPU applicatif (courbe) | Trace le CPU moyen dans le temps avec une série par microservice. | Comparer la consommation CPU de `order-service`, `inventory-service` et `restock-service`. | `process_cpu_usage` est une moyenne d’échantillons. |
| Mémoire JVM (courbe) | Trace le ratio de heap utilisée par microservice. | Détecter une croissance ou une pression mémoire. | Le ratio dépend de la valeur maximale JVM exposée. |
| CPU dans le temps (détail) | Fournit une seconde vue temporelle du CPU par microservice pour l’analyse de saturation. | Examiner les variations fines dans la période. | Vue redondante avec la courbe CPU principale. |
| Mémoire JVM dans le temps (détail) | Fournit une seconde vue temporelle de la heap par microservice. | Comparer les profils mémoire dans le temps. | Vue redondante avec la courbe mémoire principale. |
| Surcharge GC JVM | Trace la surcharge moyenne du garbage collector par microservice. | Identifier une activité GC excessive. | Une surcharge élevée doit être corrélée à la mémoire et aux latences. |
| Disponibilité des services | Affiche la disponibilité issue de la métrique `up`. | Repérer une cible non joignable. | La tuile reste une vue agrégée ; utiliser les séries techniques pour le détail. |
| Threads JVM actifs | Affiche le maximum de threads JVM observés. | Détecter une croissance anormale de la concurrence. | La tuile est agrégée ; le runtime JVM donne le détail par service. |
| Pools d’exécution Java | Affiche taille du pool, threads actifs, file d’attente et tâches terminées par service. | Détecter une saturation des exécutors. | Un service sans métrique executor peut ne pas apparaître. |
| Runtime JVM par service | Regroupe heap utilisée/max, CPU, threads actifs et uptime par microservice. | Disposer d’un état instantané comparatif des runtimes. | Les maxima de période peuvent masquer des variations brèves. |
| Liens APM | Fournit des accès directs aux vues APM Services, Transactions et Kubernetes. | Passer du signal agrégé au diagnostic détaillé. | Les liens dépendent des routes Kibana disponibles. |

## Comportement transversal attendu

- Tous les widgets respectent la période globale du dashboard.
- Les métriques techniques des microservices sont représentées par des courbes temporelles, et non par des valeurs globales ou des tableaux seuls.
- Les courbes CPU, mémoire et GC affichent une série et une légende par `resource.attributes.service.name`.
- Toute nouvelle métrique technique de microservice doit suivre cette convention de courbe temporelle ventilée par service.
- Les tableaux HTTP et Kafka agrègent des statistiques ; ils ne doivent pas afficher une simple liste de logs.
- Les widgets doivent rester lisibles lorsqu’un microservice ne publie temporairement aucune métrique.
- Les métriques PostgreSQL sont collectées dans des data streams dédiés (`postgresql.activity`, `postgresql.database`, `postgresql.statement`, `postgresql.bgwriter`) et feront l’objet d’un dashboard ou d’une section dédiée.

## Critères d’acceptation

1. Les trois microservices apparaissent dans les courbes CPU, mémoire et GC lorsqu’ils publient des données.
2. Les statistiques HTTP et Kafka affichent des agrégations et leurs dimensions fonctionnelles.
3. Une période sans données affiche un état vide explicite, sans erreur de syntaxe ES|QL.
4. Les widgets Kafka distinguent la latence du client du temps de traitement métier.
5. Les limites P95/P99 sont indiquées tant que les champs de percentile ne sont pas disponibles.
6. Toute métrique technique de microservice ajoutée au dashboard est visualisée par une courbe temporelle ventilée par service.
