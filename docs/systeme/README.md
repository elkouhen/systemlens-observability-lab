# Documentation système

Cette partie s'adresse aux opérateurs et aux personnes responsables de la
plateforme. Son objectif est de déployer, comprendre, vérifier et dépanner la
chaîne qui transporte les logs, métriques et traces jusqu'à Kibana.

Elle couvre Kubernetes, les VM, Elastic, Fleet, EDOT, Beats et les data streams.
Elle ne décrit pas le comportement métier des services ; voir plutôt la
[documentation applicative](../applicatif/README.md).

## Comprendre

1. [Architecture des signaux](architecture-signaux.md) : chemins des logs,
   métriques et traces, avec les rôles des collecteurs.
2. [Architecture Fleet](architecture-fleet.md) : plan de contrôle, policies et
   chemin de données des Elastic Agents.
3. [Comparatif des intégrations](integrations.md) : rôles respectifs de Fleet,
   Beats, EDOT et APM Server.

## Vérifier et dépanner

1. [Vérifier un signal de bout en bout](how-to/verifier-un-signal.md).
2. [Diagnostiquer un dashboard vide](how-to/diagnostiquer-dashboard-vide.md).
3. [Dépanner un Elastic Agent Fleet](how-to/depanner-fleet.md).

## Références de la plateforme

1. [Matrice des dashboards](dashboards.md) : données, champs et contrôles de
   recette par vue Kibana.
2. [Matrice des métriques et de leurs sources](metriques-sources.md) : source,
   collecteur, traitement et data stream de chaque métrique.
3. [Références partagées](../reference/objectifs.md) : objectif et critères de
   fiabilité du POC.
