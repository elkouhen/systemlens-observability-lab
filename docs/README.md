# Documentation du POC

Ce répertoire est le référentiel de compréhension du POC. Il décrit le
fonctionnement observé, les choix d'intégration et la recette des visualisations.
Il complète les README situés près de chaque configuration ; ces derniers restent
la référence d'implémentation.

Il s'adresse aux personnes techniques qui découvrent le POC ou doivent vérifier
son fonctionnement. Choisir le parcours correspondant à son objectif plutôt que
de lire nécessairement toutes les pages dans l'ordre.

## Rôles des VM

Les noms techniques des VM ne sont pas utilisés dans cette documentation. Les
rôles d'architecture suivants sont les noms de référence :

| Rôle | Collecte démontrée |
| --- | --- |
| **VM OpenTelemetry** | EDOT collecte les logs et métriques locaux. |
| **VM Elastic Agent** | Elastic Agent est administré par Fleet. |
| **VM Beats** | Filebeat et Metricbeat collectent les signaux locaux. |

## Déployer et découvrir

1. [Premier parcours de démonstration](tutorials/premiere-demonstration.md) :
   prérequis, génération d'une commande et vérification d'un log, d'une métrique
   et d'une trace.
2. Le [README à la racine du dépôt](../README.md) : prérequis complets et
   commandes de déploiement de l'environnement.

## Comprendre l'architecture

1. [Objectifs et critères de fiabilité](objectifs.md) : périmètre pédagogique,
   résultats attendus et définition d'une documentation fiable.
2. [Architecture des signaux](architecture-signaux.md) : chemins réels des logs,
   métriques et traces, avec le cycle de vie d'une trace.
3. [Comparatif des intégrations](integrations.md) : Elastic Agent/Fleet, Beats,
   OpenTelemetry et APM Server, par type de signal.
4. [Architecture Fleet](architecture-fleet.md) : rôles de Kibana, Fleet Server,
   Elastic Agent, policies, outputs et étapes de création.
5. [FAQ d'architecture](faq.md) : réponses courtes aux choix de conception et
   aux compromis de collecte.

## Vérifier et dépanner

1. [Vérifier un signal de bout en bout](how-to/verifier-un-signal.md) :
   contrôles reproductibles dans Kubernetes, les VM et Kibana.
2. [Diagnostiquer un dashboard vide](how-to/diagnostiquer-dashboard-vide.md) :
   ordre de diagnostic et requêtes KQL de départ.
3. [Dépanner un Elastic Agent Fleet](how-to/depanner-fleet.md) : vérifier
   l'enrôlement, la policy et le chemin de données.

## Références

1. [Matrice des dashboards](dashboards.md) : ce que chaque vue attend, les
   champs et les contrôles de recette.
2. [Matrice des métriques et de leurs sources](metriques-sources.md) : pour
   chaque famille de métriques, source, collecteur, transport et data stream.
3. [Technologies et sigles](technologies.md) : glossaire synthétique de la
   stack et liens vers les documentations officielles.

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
