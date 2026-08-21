# Documentation du POC

Ce répertoire est le référentiel de compréhension du POC. Il décrit le
fonctionnement observé, les choix d'intégration et la recette des visualisations.
Il complète les README situés près de chaque configuration ; ces derniers restent
la référence d'implémentation.

## Rôles des VM

Les noms techniques des VM ne sont pas utilisés dans cette documentation. Les
rôles d'architecture suivants sont les noms de référence :

| Rôle | Collecte démontrée |
| --- | --- |
| **VM OpenTelemetry** | EDOT collecte les logs et métriques locaux. |
| **VM Elastic Agent** | Elastic Agent est administré par Fleet. |
| **VM Beats** | Filebeat et Metricbeat collectent les signaux locaux. |

## Parcours recommandé

1. [Objectifs et critères de fiabilité](objectifs.md) : périmètre pédagogique,
   résultats attendus et définition d'une documentation fiable.
2. [Architecture des signaux](architecture-signaux.md) : chemins réels des logs,
   métriques et traces, avec le cycle de vie d'une trace.
3. [Comparatif des intégrations](integrations.md) : Elastic Agent/Fleet, Beats,
   OpenTelemetry et APM Server, par type de signal.
4. [Architecture Fleet](architecture-fleet.md) : rôles de Kibana, Fleet Server,
   Elastic Agent, policies, outputs et étapes de création.
5. [Matrice des dashboards](dashboards.md) : ce que chaque vue attend, les
   champs et les contrôles de recette.
6. [Matrice des métriques et de leurs sources](metriques-sources.md) : pour
   chaque famille de métriques, source, collecteur, transport et data stream.
7. [FAQ d'architecture](faq.md) : réponses courtes aux choix de conception et
   aux compromis de collecte.
8. [Technologies et sigles](technologies.md) : glossaire synthétique de la
   stack et liens vers les documentations officielles.

## Règle de mise à jour

Toute évolution de collecte doit mettre à jour au minimum : l'architecture des
signaux, la ligne correspondante de la matrice des métriques et la recette du
dashboard concerné. Une capture Kibana seule ne constitue pas une preuve : la
validation s'appuie aussi sur un document récent dans Elasticsearch et sur la
configuration versionnée qui l'a produit.
