# Objectifs du POC d'observabilité

## Objectif principal

Construire un environnement ELK **fiable, reproductible et documenté** pour
comprendre le parcours de bout en bout des logs, métriques et traces : émission,
collecte, transport, indexation Elasticsearch et visualisation Kibana.

Le code et la documentation sont deux livrables du POC : toute explication doit
pouvoir être vérifiée dans une configuration versionnée et dans les données
indexées.

## Sous-objectifs

1. Comprendre l'architecture APM : services, transactions, spans, erreurs,
   contextes distribués et métriques dérivées des traces.
2. Mettre en évidence plusieurs architectures d'intégration pour les logs,
   métriques et l'APM : Elastic Agent/Fleet, Beats, OpenTelemetry Collector,
   APM Server, et Kafka lorsqu'un tampon est utile.
3. Comparer ces solutions selon leur protocole, administration, enrichissement,
   résilience, schéma Elasticsearch, compatibilité Kibana et limites.
4. Recenser dashboard par dashboard les données attendues : data view, data
   stream, champs, filtres, fenêtre temporelle et requête de vérification.
5. Identifier pour chaque métrique sa source primaire, le composant qui la
   collecte, son transport, sa transformation éventuelle et sa destination.
6. Pouvoir rejouer une démonstration et diagnostiquer une absence de donnée sans
   dépendre de clics manuels non documentés.

## Critères d'acceptation

Le POC est considéré comme documenté de manière fiable lorsqu'une personne peut :

- déployer l'architecture avec les commandes du dépôt ;
- suivre un signal depuis son émetteur jusqu'à un document Elasticsearch ;
- expliquer pourquoi une donnée apparaît dans une vue Kibana donnée ;
- distinguer les données natives OpenTelemetry, ECS et APM ;
- trouver une procédure de contrôle quand une visualisation est vide ;
- comparer une solution active à une alternative sans confondre les rôles de
  Fleet, des Beats, de l'Agent APM et du Collector OpenTelemetry.

Les matrices [dashboards](../systeme/dashboards.md) et
[métriques/sources](../systeme/metriques-sources.md) sont les artefacts de recette de ces
critères.

## Hors périmètre actuel

Ce POC n'a pas vocation à dimensionner une plateforme de production, à définir
une rétention réglementaire ou à fournir une politique de sécurité exhaustive.
Les choix sans TLS ou sans authentification sur les réseaux internes ne sont
acceptables que parce qu'ils sont explicitement confinés au POC ; ils doivent
être réévalués pour toute cible de production.
