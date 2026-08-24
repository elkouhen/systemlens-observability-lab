# Documentation du POC

Ce répertoire est le référentiel de compréhension du POC. Il décrit le
fonctionnement observé, les choix d'intégration et la recette des visualisations.
Il complète les README situés près de chaque configuration ; ces derniers restent
la référence d'implémentation.

Il s'adresse aux personnes techniques qui découvrent le POC ou doivent vérifier
son fonctionnement. Choisir le parcours correspondant à son objectif plutôt que
de lire nécessairement toutes les pages dans l'ordre.

## Profils de collecte des VM

| Hôtes | Collecte démontrée |
| --- | --- |
| `data-01`, `data-02` | Elastic Agent 8.5.1 administré par Fleet : System, MongoDB, Kafka, Jolokia et PostgreSQL. |
| `data-03` | Filebeat et Metricbeat 8.5.1 : journaux et métriques locaux. |

## Documentation système

La documentation [système](systeme/README.md) s'adresse aux personnes qui
déploient, administrent ou dépannent Kubernetes, les VM et la chaîne Elastic.
Elle couvre les collecteurs, Fleet, les data streams et les dashboards.

## Documentation applicative

La documentation [applicative](applicatif/README.md) s'adresse aux développeurs
qui veulent comprendre les services de démonstration, générer du trafic et
vérifier l'observabilité qui en résulte.

## Références partagées

1. [Objectifs et critères de fiabilité](reference/objectifs.md) : périmètre
   pédagogique, résultats attendus et définition d'une documentation fiable.
2. [FAQ d'architecture](reference/faq.md) : réponses courtes aux choix de
   conception et aux compromis de collecte.
3. [Technologies et sigles](reference/technologies.md) : glossaire synthétique
   de la stack et liens vers les documentations officielles.
4. Le [README à la racine du dépôt](../README.md) : prérequis complets et
   commandes de déploiement de l'environnement.

## Règle de mise à jour

Toute évolution de collecte doit mettre à jour au minimum : l'architecture des
signaux, la ligne correspondante de la matrice des métriques et la recette du
dashboard concerné. Une capture Kibana seule ne constitue pas une preuve : la
validation s'appuie aussi sur un document récent dans Elasticsearch et sur la
configuration versionnée qui l'a produit.

Pour une modification opérationnelle, mettre également à jour le guide pratique
concerné et noter la version des composants ainsi que la date de la dernière
validation. Une procédure n'est fiable que si son résultat attendu est explicite
et peut être rejoué.
